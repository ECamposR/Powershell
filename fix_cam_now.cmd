@echo off
setlocal
rem Wrapper para ejecutar el fix de cámara con doble clic (UAC auto-elevado en el .ps1)

set "PS1=C:\Program Files\Mesh Agent\fix_cam_now.ps1"
if not exist "%PS1%" (
  echo [ERROR] No se encontró "%PS1%".
  echo Copie el script a esa ruta y vuelva a intentar.
  pause
  exit /b 1
)

rem MODO: quita -Silent si querés que pregunte confirmación
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Silent
if errorlevel 1 (
  echo Hubo un error ejecutando el script. Revise el log en la carpeta del script.
  pause
  exit /b 1
)

echo Listo. Si hubo incidencia, el log queda como "fix_cam_now_YYYYMMDD_HHMMSS.log" en "C:\Program Files\Mesh Agent\".
pause
endlocal

