<#
  diagnostico_bloqueos_v4.ps1
  - Log y artefactos en la MISMA carpeta del script ($PSScriptRoot).
  - Un único Transcript captura TODO (stdout/stderr/errores).
  - ZIP con archivos de esta ejecución (log + reports).
#>

[CmdletBinding()]
param(
  [int]$SinceDays = 7,
  [int]$EnergyDurationSeconds = 60,
  [switch]$EnableCrashOnCtrlScroll,
  [switch]$TryStopUrBackup,
  [switch]$TryStopGoogleDriveFS
)

# -------- Utilidades / setup --------
function Test-IsAdmin {
  $wi = [Security.Principal.WindowsIdentity]::GetCurrent()
  $wp = New-Object Security.Principal.WindowsPrincipal($wi)
  return $wp.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
if (-not (Test-IsAdmin)) { Write-Host "Ejecuta PowerShell como Administrador."; exit 1 }

# Asegura $PSScriptRoot también si se invoca de forma atípica
if (-not $PSScriptRoot) { $script:PSScriptRoot = (Get-Location).Path }

# Cierra transcripts previos (evita locks)
try { Stop-Transcript | Out-Null } catch {}

$TimeStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$OutDir    = $PSScriptRoot
$Log       = Join-Path $OutDir ("diagnostico_bloqueos_{0}.log" -f $TimeStamp)
$Since     = (Get-Date).AddDays(-1 * [Math]::Abs($SinceDays))
$Artifacts = New-Object System.Collections.Generic.List[string]

# Inicia transcript: TODO a este archivo
Start-Transcript -Path $Log -IncludeInvocationHeader | Out-Null
$Artifacts.Add($Log) | Out-Null

function Section([string]$Title) {
  $line = ('=' * 100)
  $ts   = (Get-Date -Format 'u')
  Write-Host "`n$line`n[$ts]  $Title`n$line"
}

function Run-Step([string]$Title, [scriptblock]$Body) {
  Section $Title
  try {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Stop'
    & $Body
    $ErrorActionPreference = $old
  } catch {
    Write-Warning ("ERROR en '{0}': {1}" -f $Title, $_.Exception.Message)
    if ($_.InvocationInfo.PositionMessage) {
      Write-Host ("Lugar: {0}" -f $_.InvocationInfo.PositionMessage)
    }
  }
}

function Exec-External([string]$File,[string]$Arguments='') {
  Section ("Ejecutando: {0} {1}" -f $File, $Arguments)
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = $Arguments
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($stdout) { Write-Output $stdout }
    if ($stderr) { Write-Warning ("STDERR: {0}" -f $stderr.Trim()) }
    Write-Host ("ExitCode={0}" -f $p.ExitCode)
  } catch {
    Write-Warning ("ERROR ejecutando {0} {1} : {2}" -f $File, $Arguments, $_.Exception.Message)
  }
}

# -------- Metadatos
Run-Step 'Metadatos del entorno' {
  Write-Host ("Inicio: {0}  TZ={1}" -f (Get-Date), (Get-TimeZone).Id)
  Write-Host ("Usuario: {0}" -f $env:USERNAME)
  Write-Host ("Equipo:  {0}" -f $env:COMPUTERNAME)
  Get-ComputerInfo | Out-String | Write-Output
  Get-CimInstance Win32_BIOS | Format-List * | Out-String | Write-Output
}

# -------- Eventos
Run-Step 'Eventos KernelPower 41 y 6008' {
  Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,6008; StartTime=$Since} |
    Select TimeCreated, Id, ProviderName, LevelDisplayName, Message |
    Format-Table -Wrap | Out-String | Write-Output
}
Run-Step 'WHEA errores de hardware' {
  Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$Since} |
    Select TimeCreated, Id, Message |
    Format-Table -Wrap | Out-String | Write-Output
}
Run-Step 'Display y resets de driver GPU' {
  Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Display'; StartTime=$Since} |
    Select TimeCreated, Id, Message |
    Format-Table -Wrap | Out-String | Write-Output
}
Run-Step 'Windows Error Reporting LiveKernelEvent' {
  Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Windows Error Reporting'; StartTime=$Since} |
    Where-Object { $_.Message -match 'LiveKernelEvent|TDR' -or $_.Message -match '\b141\b' } |
    Select TimeCreated, Id, Message |
    Format-Table -Wrap | Out-String | Write-Output
}
Run-Step 'VSS y volsnap' {
  Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='VSS'; StartTime=$Since} |
    Select TimeCreated, Id, Message | Format-Table -Wrap | Out-String | Write-Output
  Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='volsnap'; StartTime=$Since} |
    Select TimeCreated, Id, Message | Format-Table -Wrap | Out-String | Write-Output
}
Run-Step 'Pila almacenamiento disk storahci nvme' {
  Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$Since} |
    Where-Object { $_.ProviderName -match '^(disk|storahci|nvme)$' } |
    Select TimeCreated, ProviderName, Id, Message |
    Format-Table -Wrap | Out-String | Write-Output
}
Run-Step 'Eventos UrBackup GoogleDriveFS Sophos' {
  Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$Since} |
    Where-Object { $_.ProviderName -match 'UrBackup|Google Drive|DriveFS|Sophos' } |
    Select TimeCreated, Id, ProviderName, Message |
    Sort-Object TimeCreated |
    Format-Table -Wrap | Out-String | Write-Output

  Get-WinEvent -FilterHashtable @{LogName='System'; Id=7036; StartTime=$Since} |
    Where-Object { $_.Message -match 'UrBackup|Google Drive|DriveFS|Sophos' } |
    Select TimeCreated, Message |
    Sort-Object TimeCreated |
    Format-Table -Wrap | Out-String | Write-Output
}

# -------- Servicios / versiones
Run-Step 'Servicios clave' {
  Get-Service UrBackupClientBackend -ErrorAction SilentlyContinue |
    Select Name, Status, StartType | Format-Table | Out-String | Write-Output

  Get-Service | Where-Object {$_.Name -like 'GoogleDriveFS*' -or $_.DisplayName -like '*Google Drive*'} |
    Select Name, Status, StartType | Format-Table | Out-String | Write-Output

  Get-Service | Where-Object {$_.Name -like 'Sophos*'} |
    Select Name, Status, StartType | Format-Table | Out-String | Write-Output
}
Run-Step 'Software instalado UrBackup DriveFS Sophos' {
  $Uninst = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  Get-ItemProperty $Uninst -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match 'UrBackup|Google Drive|Sophos' } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
    Sort-Object DisplayName |
    Format-Table -Auto | Out-String | Write-Output
}

# -------- Disco y NTFS
Run-Step 'Discos fisicos y fiabilidad' {
  Get-PhysicalDisk |
    Select FriendlyName, MediaType, HealthStatus, OperationalStatus, Size |
    Format-Table -Auto | Out-String | Write-Output

  Get-PhysicalDisk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue |
    Select DeviceId, Wear, Temperature, ReadErrorsTotal, WriteErrorsTotal, PowerOnHours |
    Format-Table -Auto | Out-String | Write-Output
}
Run-Step 'Estado NTFS' {
  fsutil dirty query C: 2>&1 | Write-Output
  Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Ntfs'; StartTime=$Since} |
    Select TimeCreated, Id, Message |
    Format-Table -Wrap | Out-String | Write-Output
}

# -------- Memoria / Pagefile
Run-Step 'Memoria y pagefile' {
  Get-CimInstance Win32_OperatingSystem |
    Select @{N='TotalRAM(GB)';E={[math]::Round($_.TotalVisibleMemorySize/1MB,1)}},
           @{N='FreeRAM(GB)'; E={[math]::Round($_.FreePhysicalMemory/1MB,1)}},
           @{N='FreeVirtual(GB)';E={[math]::Round($_.FreeVirtualMemory/1MB,1)}} |
    Format-List | Out-String | Write-Output

  Get-CimInstance Win32_PageFileUsage |
    Select Name, AllocatedBaseSize, CurrentUsage, PeakUsage |
    Format-Table -Auto | Out-String | Write-Output
}

# -------- GPU / dumps
Run-Step 'Controlador de video' {
  Get-CimInstance Win32_PnPSignedDriver |
    Where-Object {$_.DeviceClass -eq 'DISPLAY'} |
    Select DeviceName, DriverVersion, DriverDate, Manufacturer |
    Format-Table -Auto | Out-String | Write-Output
}
Run-Step 'LiveKernelReports' {
  Get-ChildItem "C:\Windows\LiveKernelReports" -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match '\.dmp$' } |
    Select FullName, Length, LastWriteTime |
    Format-Table -Auto | Out-String | Write-Output
}

# -------- Integridad
Run-Step 'SFC scannow'         { Exec-External -File 'sfc.exe'   -Arguments '/scannow' }
Run-Step 'DISM RestoreHealth'  { Exec-External -File 'dism.exe'  -Arguments '/Online /Cleanup-Image /RestoreHealth' }

# -------- Energia / bateria (artefactos al mismo folder)
Run-Step ("powercfg energy {0}s" -f $EnergyDurationSeconds) {
  Exec-External -File 'powercfg.exe' -Arguments ("/energy /duration {0}" -f $EnergyDurationSeconds)
  $src = Join-Path $env:USERPROFILE 'energy-report.html'
  if (Test-Path $src) {
    $dst = Join-Path $OutDir ("energy-report_{0}.html" -f $TimeStamp)
    Move-Item $src $dst -Force
    $Artifacts.Add($dst) | Out-Null
  }
}
Run-Step 'powercfg batteryreport' {
  Exec-External -File 'powercfg.exe' -Arguments '/batteryreport'
  $src = Join-Path $env:USERPROFILE 'battery-report.html'
  if (Test-Path $src) {
    $dst = Join-Path $OutDir ("battery-report_{0}.html" -f $TimeStamp)
    Move-Item $src $dst -Force
    $Artifacts.Add($dst) | Out-Null
  }
}

# -------- VSS
Run-Step 'VSS writers' { Exec-External -File 'vssadmin.exe' -Arguments 'list writers' }
Run-Step 'VSS shadows' { Exec-External -File 'vssadmin.exe' -Arguments 'list shadows' }

# -------- Opcionales
if ($TryStopUrBackup) {
  Run-Step 'Detener UrBackup' {
    if (Get-Service UrBackupClientBackend -ErrorAction SilentlyContinue) {
      Stop-Service UrBackupClientBackend -Force -ErrorAction SilentlyContinue
      Set-Service UrBackupClientBackend -StartupType Manual
      Write-Host 'UrBackup detenido y en inicio Manual.'
    } else { Write-Host 'Servicio UrBackupClientBackend no encontrado.' }
  }
}
if ($TryStopGoogleDriveFS) {
  Run-Step 'Cerrar GoogleDriveFS' {
    Get-Process -Name GoogleDriveFS -ErrorAction SilentlyContinue |
      ForEach-Object { Write-Host ("Matando PID {0}" -f $_.Id); Stop-Process $_ -Force -ErrorAction SilentlyContinue }
  }
}
if ($EnableCrashOnCtrlScroll) {
  Run-Step 'Habilitar CrashOnCtrlScroll' {
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\kbdhid\Parameters' -Name CrashOnCtrlScroll -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\i8042prt\Parameters' -Name CrashOnCtrlScroll -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name CrashDumpEnabled -PropertyType DWord -Value 3 -Force | Out-Null
    Write-Host 'Activado. Para volcado: Ctrl derecho + Scroll Lock dos veces tras reiniciar.'
  }
}

# -------- Pistas y empaquetado
Run-Step 'Pistas rapidas' {
@'
- LiveKernelEvent 141 / eventos Display cerca del bloqueo => driver AMD.
- VSS/volsnap + UrBackup/DriveFS/Sophos en misma ventana => conflicto snapshots/copiado.
- WHEA => hardware (RAM/CPU/PCIe/GPU).
- disk/ntfs/nvme/storahci => revisar SSD/NVMe, firmware, controladores, chkdsk.
'@ | Write-Output
}

Run-Step 'Empaquetar resultados' {
  $Zip = Join-Path $OutDir ("diag_bloqueos_{0}.zip" -f $TimeStamp)
  if (Test-Path $Zip) { Remove-Item $Zip -Force }
  if ($Artifacts.Count -gt 0) {
    Compress-Archive -Path $Artifacts.ToArray() -DestinationPath $Zip -Force
    Write-Host ("ZIP: {0}" -f $Zip)
  } else {
    Write-Host "No hay artefactos para comprimir."
  }
}

Stop-Transcript | Out-Null
Write-Host ("`nListo. Log: {0}" -f $Log)
