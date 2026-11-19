# Reenvia hacia WSL2 el puerto publicado por Docker Compose (el del contenedor web, 8080 por
# defecto) para que otras PCs de la red -no solo este mismo equipo- puedan alcanzar la API de
# SGLAB. Es necesario porque WSL2 usa NAT: Windows solo reenvia automaticamente a WSL el
# trafico que llega por localhost/127.0.0.1, no el que llega desde otra PC a la IP de este
# equipo en la red.
#
# Ejecutar como Administrador. Es idempotente: se puede volver a correr en cualquier momento
# (por ejemplo, cada vez que arranca Windows, ya que la IP interna de WSL cambia en cada
# reinicio - ver instalar-exposicion-wsl.ps1 para automatizar eso).
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

$wslIp = ((wsl hostname -I) -split '\s+')[0]
if (-not $wslIp) {
    Write-Output "No se pudo obtener la IP de WSL. ¿Esta WSL corriendo? Probar: wsl -d <distro> hostname -I"
    exit 1
}

Write-Output "IP actual de WSL: $wslIp"

netsh interface portproxy delete v4tov4 listenport=$puerto listenaddress=0.0.0.0 | Out-Null
netsh interface portproxy add v4tov4 listenport=$puerto listenaddress=0.0.0.0 connectport=$puerto connectaddress=$wslIp | Out-Null
Write-Output "Puerto $puerto redirigido hacia ${wslIp}:$puerto"

$nombreRegla = "SGLAB-WSL-$puerto"
if (-not (Get-NetFirewallRule -DisplayName $nombreRegla -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $nombreRegla -Direction Inbound -Protocol TCP -LocalPort $puerto -Action Allow | Out-Null
    Write-Output "Regla de firewall creada: $nombreRegla"
}

Write-Output "Listo. Otras PCs de la red ya pueden alcanzar http://<IP-de-este-equipo>:$puerto"
