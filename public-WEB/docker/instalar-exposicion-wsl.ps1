# Registra una Tarea Programada que reaplica exponer-wsl-en-red.ps1 cada vez que arranca
# Windows - necesario porque la IP interna de WSL cambia en cada reinicio, por lo que el
# reenvio de puerto hecho a mano se rompe despues de reiniciar la PC o solo reiniciar WSL.
#
# Ejecutar una vez, como Administrador, en la PC que corre el servidor Docker (no en las PCs
# de los alumnos - eso es ps/instalar-agente.ps1).
param(
    [int]$puerto = 8080
)

function Test-Administrador {
    $actual = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($actual)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrador)) {
    Write-Output "Este script debe ejecutarse como Administrador."
    exit 1
}

$nombreTarea = "SGLAB-Exponer-WSL"
$rutaScript = Join-Path $PSScriptRoot "exponer-wsl-en-red.ps1"

if (-not (Test-Path $rutaScript)) {
    Write-Output "No se encontro exponer-wsl-en-red.ps1 en: $rutaScript"
    exit 1
}

$accion = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$rutaScript`" -puerto $puerto"

$disparador = New-ScheduledTaskTrigger -AtStartup
$configuracion = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $nombreTarea -Action $accion -Trigger $disparador `
    -Settings $configuracion -Principal $principal -Force `
    -Description "Reexpone a la red el puerto $puerto de Docker (WSL2) cada vez que arranca Windows." | Out-Null

Write-Output "Tarea '$nombreTarea' instalada: se ejecuta al iniciar Windows."

# Aplicar de inmediato, sin esperar al proximo arranque de Windows.
Write-Output ""
Write-Output "Aplicando la exposicion del puerto ahora mismo..."
& $rutaScript -puerto $puerto
