# Script PowerShell: Diagnóstico del PC y exportación en formato TOML con clave SSH
param(
    [int]$cedula = 0
)

# Servidor SGLAB (Docker): URL del endpoint. Se puede sobreescribir con la variable de entorno
# SGLAB_API_URL sin tocar el script, util porque la IP real del servidor cambia segun la red
# donde se despliegue (ej. red de pruebas Ceibal vs. la red del MikroTik del laboratorio).
# Valor por defecto: IP del servidor detectada en la red del MikroTik del laboratorio
# (192.168.88.0/24, gateway 192.168.88.1). Si el servidor recibe otra IP por DHCP, actualizar
# este valor o asignarle una IP estatica fuera del rango DHCP (ver doc/REGISTRO_PS1.md).
$apiUrl = if ($env:SGLAB_API_URL) { $env:SGLAB_API_URL } else { "http://192.168.88.190:8080/api/api_registro.php" }
# Debe coincidir con API_SECRET_KEY en public-WEB/.env
$apiKey = if ($env:SGLAB_API_KEY) { $env:SGLAB_API_KEY } else { "CAMBIAR_ESTA_CLAVE" }
# Debe coincidir con Laboratorios.nombre en la base de datos
$laboratorio = "Laboratorio 6"
$clavePrivada = Join-Path $env:USERPROFILE ".ssh/id_rsa"

# Carpeta propia del agente para reportes y log (no el Escritorio: el agente corre
# repetidamente en segundo plano vía Tarea Programada y no debe ensuciar el Escritorio).
$carpetaDatos = Join-Path $env:LOCALAPPDATA "SGLAB"
$carpetaReportes = Join-Path $carpetaDatos "Reportes"
$archivoLog = Join-Path $carpetaDatos "agente.log"
New-Item -ItemType Directory -Path $carpetaReportes -Force | Out-Null

function Escribir-Log {
    param([string]$mensaje)
    $linea = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $mensaje"
    Add-Content -Path $archivoLog -Value $linea
    Write-Output $mensaje
}

Escribir-Log "Iniciando ejecucion del agente SGLAB"

# Obtener fecha y nombre del equipo
$fecha = Get-Date -Format "yyyyMMdd"
$fechaLegible = Get-Date -Format "yyyy/MM/dd (HH:mm)"
$nombrePC = $env:COMPUTERNAME
$serialPC = $((Get-CimInstance Win32_BIOS).SerialNumber)
$serial = "$serialPC".Trim()
if (-not $serial) { $serial = $nombrePC }
# Función para generar clave SSH si no existe
function New-SSHKey {
    $sshDir = "$env:USERPROFILE\.ssh"
    $privateKeyPath = "$sshDir\id_rsa"
    $publicKeyPath = "$sshDir\id_rsa.pub"
    
    if (!(Test-Path $sshDir)) {
        try {
            New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
            Write-Output "Directorio .ssh creado"
        }
        catch {
            Write-Output "Error al crear directorio .ssh: $($_.Exception.Message)"
            return "ERROR: No se pudo crear el directorio .ssh"
        }
    }
    
    if (Test-Path $publicKeyPath) {
        try {
            $claveExistente = Get-Content $publicKeyPath -Raw
            return $claveExistente
        }
        catch {
            Write-Output "Error al leer la clave existente: $($_.Exception.Message)"
            return "ERROR: No se pudo leer la clave SSH existente"
        }
    }
    else {
         Write-Output "Generando nueva clave SSH..."
        Write-Output "Directorio .ssh = $sshDir"
        try {
            Get-Command ssh-keygen -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Output "ssh-keygen no está disponible en el sistema"
            return "ERROR: ssh-keygen no disponible. Instale OpenSSH Client."
        }
        $sshKeygenArgs = @(
            "-t", "rsa",
            "-b", "2048", 
            "-f", $privateKeyPath,
            "-N", '""',
            "-C", "$env:USERNAME@$env:COMPUTERNAME"
        )
    
        try {
            & ssh-keygen @sshKeygenArgs
            if (Test-Path $publicKeyPath) {
                Write-Output "Clave SSH generada exitosamente"
                $nuevaClave = Get-Content $publicKeyPath -Raw
                return $nuevaClave
            }
            else {
                Write-Output "Error al generar la clave SSH"
                return "ERROR: No se pudo generar la clave SSH"
            }
        }
        catch {
            Write-Output "Error ejecutando ssh-keygen: $_"
            return "ERROR: ssh-keygen falló - $($_.Exception.Message)"
        }
    }
}

   

# Generar o obtener clave SSH pública
Write-Output "========== GESTION DE CLAVES SSH =========="
$clavePublica = New-SSHKey
Write-Output "=========================================="

# Intentar hacer ping al Gateway
Write-Output "Verificando conectividad..."
try {
    # Con varias interfaces (VPN, WSL, Hyper-V) se usa la ruta que Windows prefiere
    $ruta = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
        Sort-Object { $_.RouteMetric + $_.InterfaceMetric } |
        Select-Object -First 1
    $gateway = $ruta.NextHop
    $ping = Test-Connection -ComputerName $gateway -Count 1 -Quiet
    if ($ping) {
        $estado = "Exito"
    }
    else {
        $estado = "Fallo"
    }
}
catch {
    $estado = "Error"
    $gateway = "No disponible"
}

# Obtener información del sistema
Write-Output "Recopilando información del sistema..."
try {
    $so = Get-CimInstance Win32_OperatingSystem
    $filtroIP = @{ AddressFamily = "IPv4" }
    if ($ruta) { $filtroIP.InterfaceIndex = $ruta.InterfaceIndex }
    $ipInfo = Get-NetIPAddress @filtroIP | Where-Object {$_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual"} | Select-Object -First 1
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cpuUso = [int]$cpu.LoadPercentage
    $ram = [math]::Round($so.TotalVisibleMemorySize / 1024 / 1024, 2)
    $disco = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $discoTotal = [math]::Round($disco.Size / 1GB, 2)
    $discoLibre = [math]::Round($disco.FreeSpace / 1GB, 2)
    $discoUso = [math]::Round(($disco.Size - $disco.FreeSpace) / $disco.Size * 100, 2)
    $ramUsoPorc = [math]::Round(($so.TotalVisibleMemorySize - $so.FreePhysicalMemory) / $so.TotalVisibleMemorySize * 100, 2)
    $discoTipo = "Desconocido"
    try {
        $numeroDisco = (Get-Partition -DriveLetter C -ErrorAction Stop).DiskNumber
        $discoFisico = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq "$numeroDisco" }
        if ($discoFisico.MediaType) { $discoTipo = "$($discoFisico.MediaType)" }
    }
    catch {
        Write-Output "No se pudo determinar el tipo de disco: $($_.Exception.Message)"
    }
}
catch {
    Escribir-Log "ERROR - No se pudo recopilar informacion del sistema: $($_.Exception.Message)"
    exit 1
}

# Función para validar cédula uruguaya con dígito verificador
function Test-CedulaUruguaya {
    param([string]$cedula)

    # Verificar formato básico (1-9 dígitos)
    if ($cedula -notmatch '^\d{1,9}$') {
        return $false
    }

    # Algoritmo de validación de cédula uruguaya
    $cedulaStr = $cedula.PadLeft(7, '0')
    $digitos = $cedulaStr.ToCharArray() | ForEach-Object { [int]::Parse($_) }

    # Coeficientes: 2,9,8,7,6,3,4
    $coeficientes = @(2,9,8,7,6,3,4)
    $suma = 0

    for ($i = 0; $i -lt 7; $i++) {
        $suma += $digitos[$i] * $coeficientes[$i]
    }

    $resto = $suma % 10
    $digitoVerificador = if ($resto -eq 0) { 0 } else { 10 - $resto }

    # Si tiene 8 dígitos, validar el último como verificador
    if ($cedula.Length -eq 9) {
        $ultimoDigito = [int]::Parse($cedula.Substring(8, 1))
        return $ultimoDigito -eq $digitoVerificador
    }

    # Si tiene menos de 8 dígitos, es válida (no incluye verificador)
    return $true
}

# Solicitar y validar cédula del usuario
if ($cedula -eq 0) {
    Write-Output "Ejecutando en modo desatendido con cedula = 0"
} else {
    # Si se pasó parámetro diferente de 0, solicitar cédula
    do {
        $inputCedula = Read-Host "Ingrese su cedula (maximo 9 digitos con digito verificador 1234567-8)"
        $cedulaValida = Test-CedulaUruguaya $inputCedula
        if (-not $cedulaValida) {
            Write-Output "Cédula inválida. Debe contener solo números (1-9   dígitos) y tener dígito verificador válido si tiene 8 dígitos."
        } else {
            $cedula = [int]$inputCedula
        }
    } until ($cedulaValida)
}

# Ruta y nombre de archivo de salida (un archivo por día por equipo; se sobrescribe
# en corridas sucesivas del mismo día para no acumular archivos en cada ejecución del agente)
$archivo = Join-Path $carpetaReportes "$fecha-$nombrePC-$serial.toml"

# Crear contenido TOML
$contenido = @"
[info_general]
serial = "$serial"
fecha = "$($fechaLegible)"
nombre_pc = "$($nombrePC)"
estado_conexion = "$($estado)"

[sistema_operativo]
nombre = "$($so.Caption)"
version = "$($so.Version)"

[red]
ip = "$($ipInfo.IPAddress)"
mascara = "$($ipInfo.PrefixLength)"
default_gateway = "$($gateway)"


[hardware]
cpu = "$($cpu.Name)"
ram_gb = $ram
disco_c_gb = $discoTotal

[ssh]
clave_publica = "$($clavePublica.Trim())"
usuario = "$($env:USERNAME)"
ruta_clave = "$($clavePrivada + '.pub')"

[usuario_responsable]
cedula = "$cedula"

#[diagnostico_red]
#LAN = "$($pingLAN -replace 'True','Exito' -replace 'False','Fallo')"
#WAN = "$($pingWAN -replace 'True','Exito' -replace 'False','Fallo')"
#DHCP = "$($usaDHCP -replace 'True','Exito' -replace 'False','Fallo')"
#DNS = "$($dnsOK -replace 'True','Exito' -replace 'False','Fallo')"

[recursos_disponibles]
cpu_uso_porcentaje = $cpuUso
ram_uso_porcentaje = $ramUsoPorc
disco_c_uso_porcentaje = $discoUso

"@

# Guardar archivo
try {
    $contenido | Out-File -FilePath $archivo -Encoding utf8
    Write-Output "Archivo TOML guardado: $archivo"
}
catch {
    Escribir-Log "ERROR - No se pudo guardar archivo local $archivo : $($_.Exception.Message)"
    Write-Output "========== SCRIPT con ERROR=========="
    exit 1
}

# Mostrar información en consola
Write-Output ""
Write-Output "========== DIAGNOSTICO COMPLETADO =========="
Write-Output "Archivo generado: $archivo"
Write-Output "API SGLAB: $apiUrl"
Write-Output ""
Write-Output "========== CLAVE SSH PUBLICA =========="
Write-Output $clavePublica
Write-Output "======================================"

# Enviar el reporte a SGLAB, que lo guarda en la base de datos
$reporte = [ordered]@{
    serial          = $serial
    hostname        = $nombrePC
    laboratorio     = $laboratorio
    cedula          = $cedula
    estado          = ($estado -eq "Exito")
    ip              = "$($ipInfo.IPAddress)"
    mascara         = "$($ipInfo.PrefixLength)"
    gateway         = "$gateway"
    so              = "$($so.Caption)"
    so_version      = "$($so.Version)"
    usuario_windows = $env:USERNAME
    cpu             = "$($cpu.Name)".Trim()
    ram_gb          = $ram
    disco_tipo      = $discoTipo
    disco_total_gb  = $discoTotal
    disco_libre_gb  = $discoLibre
    cpu_uso         = $cpuUso
    ram_uso         = $ramUsoPorc
    disco_uso       = $discoUso
}

try {
    # Se envian bytes UTF-8: Windows PowerShell 5.1 no lo hace por defecto
    $cuerpo = [Text.Encoding]::UTF8.GetBytes(($reporte | ConvertTo-Json))
    $respuesta = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $cuerpo -TimeoutSec 15 `
        -ContentType "application/json; charset=utf-8" -Headers @{ "X-API-KEY" = $apiKey }
    Escribir-Log "OK - Respuesta de SGLAB: $($respuesta.mensaje) (serial: $serial)"
    Write-Output "========== SCRIPT COMPLETADO con EXITO=========="
}
catch {
    $detalle = if ($_.ErrorDetails.Message) { " | Detalle: $($_.ErrorDetails.Message)" } else { "" }
    Escribir-Log "ERROR - No se pudo enviar el reporte a ${apiUrl}: $($_.Exception.Message)$detalle"
    Write-Output "Tu direccion IP actual es: $($ipInfo.IPAddress). El reporte quedo guardado en $archivo"
    Write-Output "========== SCRIPT con ERROR=========="
    exit 1
}
