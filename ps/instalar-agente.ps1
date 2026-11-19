# Instala el agente SGLAB como Tarea Programada de Windows: ejecuta registro.ps1
# en segundo plano cada cierto intervalo (por defecto 15 minutos), sin ventana visible.
# Requiere PowerShell en modo Administrador.
param(
    [int]$intervaloMinutos = 15,
    [switch]$sinSesionIniciada  # Corre como SYSTEM, incluso sin ningun usuario logueado
)

$nombreTarea = "SGLAB-Agente-Inventario"
$rutaScript = Join-Path $PSScriptRoot "registro.ps1"

if (-not (Test-Path $rutaScript)) {
    Write-Output "No se encontro registro.ps1 en: $rutaScript"
    exit 1
}

$accion = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$rutaScript`""

$disparador = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $intervaloMinutos) `
    -RepetitionDuration ([TimeSpan]::MaxValue)

$configuracion = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew -Hidden

if ($sinSesionIniciada) {
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
} else {
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
}

Register-ScheduledTask -TaskName $nombreTarea -Action $accion -Trigger $disparador `
    -Settings $configuracion -Principal $principal -Force `
    -Description "Agente SGLAB: recolecta inventario del equipo y lo envia a la API cada $intervaloMinutos minutos." | Out-Null

Write-Output "Tarea programada '$nombreTarea' instalada: corre cada $intervaloMinutos minutos."
Write-Output "Log del agente: $env:LOCALAPPDATA\SGLAB\agente.log"
Write-Output "Para ver el estado:   Get-ScheduledTask -TaskName '$nombreTarea' | Get-ScheduledTaskInfo"
Write-Output "Para forzar una corrida ya: Start-ScheduledTask -TaskName '$nombreTarea'"
Write-Output "Para desinstalar:     Unregister-ScheduledTask -TaskName '$nombreTarea' -Confirm:`$false"
