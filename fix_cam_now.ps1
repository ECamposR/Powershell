<#
  fix_cam_now.ps1
  - Recupera la cámara sin reiniciar (FrameServer/UVC reset).
  - Crea log en la MISMA carpeta del script con fecha/hora.
  - Captura eventos útiles (WER 141, Kernel-PnP, Display) y datos del driver.
#>

[CmdletBinding()]
param(
  [int]$WindowMinutes = 120,           # ventana forense
  [switch]$Silent                      # sin confirmaciones
)

# --- Auto-elevación UAC ---
function Test-IsAdmin {
  $wi=[Security.Principal.WindowsIdentity]::GetCurrent()
  $wp=New-Object Security.Principal.WindowsPrincipal($wi)
  return $wp.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
  $argsList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
  if ($WindowMinutes) { $argsList += @('-WindowMinutes', $WindowMinutes) }
  if ($Silent)        { $argsList += '-Silent' }
  Start-Process -FilePath 'powershell.exe' -ArgumentList $argsList -Verb RunAs
  exit
}

# --- Setup / logging ---
if (-not $PSScriptRoot) { $script:PSScriptRoot = (Get-Location).Path }
$ts   = Get-Date -Format 'yyyyMMdd_HHmmss'
$Log  = Join-Path $PSScriptRoot ("fix_cam_now_{0}.log" -f $ts)
try { Stop-Transcript | Out-Null } catch {}
Start-Transcript -Path $Log -IncludeInvocationHeader | Out-Null

# Utilidades
function Section($t){ $l=('='*90); Write-Host "`n$l`n[$(Get-Date -Format u)] $t`n$l" }
function Try-Do([string]$What,[scriptblock]$Body){
  Section $What
  try { & $Body } catch { Write-Warning ("ERROR {0}: {1}" -f $What, $_.Exception.Message) }
}

# Confirmación (opcional)
if (-not $Silent){
  Add-Type -AssemblyName System.Windows.Forms
  $msg = "Se reiniciará la canalización de cámara, se cerrarán apps que puedan retenerla (Zoom, navegadores, etc.) y se reseteará el dispositivo UVC. ¿Continuar?"
  $ans = [System.Windows.Forms.MessageBox]::Show($msg,"Recuperar cámara", [System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question)
  if ($ans -ne [System.Windows.Forms.DialogResult]::Yes){ Stop-Transcript | Out-Null; exit }
}

$from = (Get-Date).AddMinutes(-1*[Math]::Abs($WindowMinutes))

# --- Forense rápido previo ---
Try-Do "Info de cámara/driver" {
  Get-CimInstance Win32_PnPSignedDriver |
    Where-Object { $_.DeviceClass -in @('Camera','Image') } |
    Select DeviceName, DriverVersion, DriverDate, Manufacturer, InfName |
    Format-Table -Auto | Out-String | Write-Output
  $cams = Get-PnpDevice -Class Camera -PresentOnly -ErrorAction SilentlyContinue
  if ($cams){
    $cams | Select Class, FriendlyName, Status, InstanceId | Format-Table -Auto | Out-String | Write-Output
    foreach($c in $cams){
      Get-PnpDeviceProperty -InstanceId $c.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction SilentlyContinue |
        ForEach-Object { "HWID: " + ($_.Data -join ', ') } | Write-Output
    }
  } else { Write-Host "No se detectaron dispositivos de cámara (Class=Camera)." }
}

Try-Do "Eventos recientes (WER 141/TDR)" {
  Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Windows Error Reporting'; StartTime=$from} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'LiveKernelEvent|TDR|\b141\b' } |
    Select TimeCreated, Id, Message | Format-Table -Wrap | Out-String | Write-Output
}
Try-Do "Eventos recientes (Display)" {
  Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Display'; StartTime=$from} -ErrorAction SilentlyContinue |
    Select TimeCreated, Id, Message | Format-Table -Wrap | Out-String | Write-Output
}
Try-Do "Eventos recientes (Kernel-PnP)" {
  Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-PnP'; StartTime=$from} -ErrorAction SilentlyContinue |
    Select TimeCreated, Id, Message | Format-Table -Wrap | Out-String | Write-Output
}

# --- Recuperación ---
Try-Do "Reinicio de servicios de captura" {
  'FrameServer','stisvc','camsvc' | ForEach-Object {
    $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
    if ($svc){ Restart-Service $svc -Force -ErrorAction SilentlyContinue; (Get-Service $svc.Name).Status | Out-String | Write-Output }
    else { Write-Host "Servicio $_ no presente." }
  }
}

Try-Do "Cerrar procesos que pueden retener la cámara" {
  $procs = 'zoom','WindowsCamera','camera','msedge','chrome','teams','obs64','obs','discord','skype'
  foreach($p in $procs){
    Get-Process -Name $p -ErrorAction SilentlyContinue | ForEach-Object {
      Write-Host ("Matando {0} (PID {1})" -f $_.ProcessName, $_.Id)
      Stop-Process $_ -Force -ErrorAction SilentlyContinue
    }
  }
}

Try-Do "Reset PnP de dispositivos de cámara (disable/enable)" {
  $cams = Get-PnpDevice -Class Camera -PresentOnly -ErrorAction SilentlyContinue
  if ($cams){
    foreach($d in $cams){
      Write-Host ("Deshabilitando: {0}" -f $d.InstanceId)
      pnputil /disable-device "$($d.InstanceId)" /force | Out-String | Write-Output
      Start-Sleep -Seconds 3
      Write-Host ("Habilitando: {0}" -f $d.InstanceId)
      pnputil /enable-device "$($d.InstanceId)"  | Out-String | Write-Output
    }
  } else { Write-Host "No hay dispositivos de cámara presentes para resetear." }
}

# --- Verificación post ---
Try-Do "Comprobación post-reset" {
  Get-PnpDevice -Class Camera -PresentOnly -ErrorAction SilentlyContinue |
    Select Class, FriendlyName, Status, InstanceId | Format-Table -Auto | Out-String | Write-Output
}

# --- Fin / Notificación ---
try { Stop-Transcript | Out-Null } catch {}
if (-not $Silent){
  Add-Type -AssemblyName System.Windows.Forms
  [System.Windows.Forms.MessageBox]::Show("Proceso finalizado. Reabre Zoom o la app Cámara y prueba nuevamente.`nLog: $Log",
    "Recuperar cámara - Completado",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
} else { Write-Host "Listo. Log: $Log" }
