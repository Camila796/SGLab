echo off
set USUARIO=%USERNAME%
echo Configurando el agente SGLAB para el usuario: %USUARIO%
echo Este script debe ejecutarse desde una consola de PowerShell/CMD en modo Administrador.
echo.
echo Instalando el agente como Tarea Programada (corre en segundo plano cada 15 minutos)...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar-agente.ps1"

copy "C:\Users\%USUARIO%\SGLAB\ps\registro-estudiante.lnk "C:\Users\%USUARIO%\Desktop\registro-estudiante.lnk"
echo Acceso directo creado en el escritorio (ejecucion manual bajo demanda).
echo.
echo Configuracion completada.
pause