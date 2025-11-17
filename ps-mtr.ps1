param(
  [Parameter(Mandatory=$true)][string]$Target,
  [int]$MaxHops = 30,
  [int]$IntervalMs = 1000,
  [int]$TimeoutMs = 800,
  [int]$Window = 50,
  [switch]$NoDNS
)

# --- Descubrir ruta una vez (tracert) ---
$tracertArgs = @($Target, "-h", $MaxHops)
if ($NoDNS) { $tracertArgs = @("-d", $Target, "-h", $MaxHops) }

$hops = & tracert @tracertArgs 2>$null |
  Select-String -Pattern '^\s*\d+\s+([0-9\.]+)$','^\s*\d+\s+([0-9a-fA-F:]+)$','^\s*\d+\s+([\w\.-]+)\s+\[([0-9a-fA-F\.:]+)\]' |
  ForEach-Object {
    $m = $_.Matches[0].Groups
    if ($m.Count -ge 2) { $m[$m.Count-1].Value }
  } | Where-Object { $_ -and $_ -ne '*' } | Select-Object -Unique

if (-not $hops -or $hops.Count -eq 0) {
  Write-Host "No se pudieron obtener hops hacia $Target" -ForegroundColor Red
  exit 1
}

# --- Estructuras de estado ---
$stats = @{}
foreach ($h in $hops) {
  $stats[$h] = [PSCustomObject]@{
    Sent=0; Recv=0; Loss=0.0;
    LastMs=$null; AvgMs=$null; BestMs=$null; WorstMs=$null;
    Samples = New-Object System.Collections.Generic.Queue[double]
  }
}

function Update-HopStats {
  param([string]$Hop,[Nullable[Double]]$rttMs)
  $s = $stats[$Hop]
  $s.Sent++

  if ($rttMs.HasValue) {
    $s.Recv++
    $s.LastMs = [math]::Round($rttMs.Value,1)
    if ($s.BestMs -eq $null -or $rttMs.Value -lt $s.BestMs) { $s.BestMs = $rttMs.Value }
    if ($s.WorstMs -eq $null -or $rttMs.Value -gt $s.WorstMs) { $s.WorstMs = $rttMs.Value }
    $s.Samples.Enqueue($rttMs.Value)
    while ($s.Samples.Count -gt $Window) { $null = $s.Samples.Dequeue() }
    $s.AvgMs = [math]::Round(($s.Samples | Measure-Object -Average).Average,1)
  }
  $s.Loss = if ($s.Sent -gt 0) { [math]::Round((1 - ($s.Recv / $s.Sent))*100,1) } else { 0.0 }
}

# --- Bucle "en vivo" ---
$ESC = [char]27
function Clear-Screen { Write-Host "$ESC[2J$ESC[H" -NoNewline }

while ($true) {
  foreach ($hop in $hops) {
    try {
      $r = Test-Connection -TargetName $hop -Count 1 -TimeoutMilliseconds $TimeoutMs -ErrorAction Stop
      $rtt = [double]$r.Latency
      Update-HopStats -Hop $hop -rttMs $rtt
    } catch {
      Update-HopStats -Hop $hop -rttMs $null
    }
  }

  Clear-Screen
  Write-Host ("ps-mtr hacia {0} ({1} hops) ventana {2} - Ctrl+C para salir" -f $Target,$hops.Count,$Window)
  "{0,-4} {1,-40} {2,6} {3,7} {4,7} {5,7} {6,7}" -f "#","Hop","Loss%","Last","Avg","Best","Worst" | Write-Host
  "{0}" -f ("-"*88) | Write-Host

  $i=1
  foreach ($hop in $hops) {
    $s = $stats[$hop]
    $name = if ($NoDNS) { $hop } else {
      try { [System.Net.Dns]::GetHostEntry($hop).HostName } catch { $hop }
    }

    $last  = if ($s.LastMs)  { $s.LastMs }  else { "-" }
    $avg   = if ($s.AvgMs)   { $s.AvgMs }   else { "-" }
    $best  = if ($s.BestMs)  { $s.BestMs }  else { "-" }
    $worst = if ($s.WorstMs) { $s.WorstMs } else { "-" }

    "{0,-4} {1,-40} {2,6:N1} {3,7} {4,7} {5,7} {6,7}" -f `
      $i, $name.Substring(0,[math]::Min(40,$name.Length)),
      $s.Loss,$last,$avg,$best,$worst | Write-Host
    $i++
  }

  Start-Sleep -Milliseconds $IntervalMs
}

