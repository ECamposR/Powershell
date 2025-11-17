$code = @'
param([int]$WindowMinutes = 6)
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$State = Join-Path $Root 'tdr_state.json'
$Csv   = Join-Path $Root 'tdr_events.csv'

if (-not (Test-Path $State)) {
  $init = @{ LastTime = (Get-Date).AddMinutes(-$WindowMinutes).ToString('o') }
  $init | ConvertTo-Json | Set-Content -Encoding UTF8 $State
  if (-not (Test-Path $Csv)) {
    "TimeCreated,Source,Id,Summary" | Set-Content -Encoding UTF8 $Csv
  }
}

$last = (Get-Content $State | ConvertFrom-Json).LastTime
$since = [datetime]::Parse($last)

# Display provider (resets/TDR, p.ej. 4101) y WER LiveKernelEvent 141
$ev1 = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Display'; StartTime=$since} -ErrorAction SilentlyContinue
$ev2 = Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Windows Error Reporting'; StartTime=$since} -ErrorAction SilentlyContinue |
       Where-Object { $_.Message -match 'LiveKernelEvent|TDR|\b141\b' }

$all = @($ev1 + $ev2) | Sort-Object TimeCreated
foreach ($e in $all) {
  $msg = ($e.Message -replace "[\r\n]+"," ") -replace '"',''''
  $line = '{0},"{1}",{2},"{3}"' -f $e.TimeCreated.ToString('u'), $e.ProviderName, $e.Id, ($msg.Substring(0,[Math]::Min(300,$msg.Length)))
  Add-Content -Path $Csv -Value $line
}

# Avanza el marcador de tiempo (pequeño margen para no perder nada)
$now = (Get-Date).AddSeconds(-10).ToString('o')
@{ LastTime = $now } | ConvertTo-Json | Set-Content -Encoding UTF8 $State
'@
New-Item -Type Directory C:\Tools -Force | Out-Null
Set-Content -Path C:\Tools\monitor_tdr.ps1 -Value $code -Encoding UTF8

