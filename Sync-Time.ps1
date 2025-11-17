#requires -RunAsAdministrator
<#
.SYNOPSIS
  Sincroniza fecha/hora al inicio del sistema en equipos fuera de dominio.
.DESCRIPTION
  - Espera que haya red
  - Ajusta zona horaria (por defecto: "Central America Standard Time" – El Salvador, UTC-6 sin DST)
  - Configura orígenes NTP y el servicio w32time
  - Fuerza resync con reintentos
  - Registra acciones en C:\Windows\Temp\TimeSync.log
#>

$ErrorActionPreference = 'Stop'
$LogFile = 'C:\Windows\Temp\TimeSync.log'

function Write-Log {
    param([string]$Msg)
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -Path $LogFile -Value "[$stamp] $Msg"
}

try {
    Write-Log "==== Inicio de Sync-Time.ps1 ===="

    # 1) Zona horaria (ajusta si no estás en El Salvador)
    $DesiredTZ = 'Central America Standard Time'  # El Salvador (UTC-06, sin DST)
    try {
        $currentTZ = (tzutil /g) 2>$null
        if ($currentTZ -ne $DesiredTZ) {
            tzutil /s "$DesiredTZ"
            Write-Log "Zona horaria establecida en: $DesiredTZ (antes: $currentTZ)"
        } else {
            Write-Log "Zona horaria ya correcta: $currentTZ"
        }
    } catch {
        Write-Log "No se pudo leer/establecer zona horaria: $_"
    }

    # 2) Esperar conectividad de red (ICMP) hasta 2 minutos
    $Targets = @('1.1.1.1','8.8.8.8')
    $MaxWaitSec = 120
    $Waited = 0
    $HasNet = $false
    while ($Waited -lt $MaxWaitSec -and -not $HasNet) {
        foreach ($t in $Targets) {
            try {
                if (Test-Connection -TargetName $t -Count 1 -Quiet -ErrorAction Stop) {
                    $HasNet = $true
                    break
                }
            } catch { Start-Sleep -Seconds 1 }
        }
        if (-not $HasNet) {
            Start-Sleep -Seconds 3
            $Waited += 3
        }
    }
    Write-Log ("Conectividad de red: " + ($HasNet ? "OK" : "NO"))

    # 3) Configurar servicio Windows Time
    $NtpPeers = 'time.windows.com,0x9 time.google.com,0x9 pool.ntp.org,0x9'
    Set-Service -Name W32Time -StartupType Automatic
    & w32tm /config /manualpeerlist:"$NtpPeers" /syncfromflags:manual /reliable:yes /update | Out-Null
    Write-Log "NTP peers configurados: $NtpPeers"
    Restart-Service W32Time -Force
    Write-Log "Servicio W32Time reiniciado"

    # 4) Reintentos de sincronización (por si el reloj está muy fuera de rango)
    $MaxRetries = 6
    $DelaySec   = 20
    $Success = $false
    for ($i=1; $i -le $MaxRetries -and -not $Success; $i++) {
        try {
            & w32tm /resync /force 2>&1 | Tee-Object -Variable res
            if ($LASTEXITCODE -eq 0 -or ($res -join "`n") -match 'The command completed successfully') {
                $Success = $true
                Write-Log "Sincronización correcta en intento #$i"
                break
            } else {
                Write-Log "Intento #$i falló. Salida: $($res -join ' | ')"
            }
        } catch {
            Write-Log "Error en intento #$i: $_"
        }
        Start-Sleep -Seconds $DelaySec
    }

    if (-not $Success) {
        # A veces ayuda “re-anclar” el origen y volver a intentar una vez más
        & w32tm /config /update | Out-Null
        Start-Sleep -Seconds 5
        & w32tm /resync /force 2>&1 | Tee-Object -Variable lastTry
        if ($LASTEXITCODE -eq 0 -or ($lastTry -join "`n") -match 'The command completed successfully') {
            $Success = $true
            Write-Log "Sincronización correcta tras reconfigurar origen."
        } else {
            Write-Log "Fallo final de sincronización. Salida: $($lastTry -join ' | ')"
        }
    }

    # 5) Estado final
    try {
        $status = & w32tm /query /status 2>&1
        Write-Log "Estado w32tm:`n$status"
        $peers  = & w32tm /query /peers 2>&1
        Write-Log "Peers w32tm:`n$peers"
    } catch {
        Write-Log "No se pudo consultar estado/peers: $_"
    }

    Write-Log "==== Fin de Sync-Time.ps1 (Éxito=$Success) ===="
} catch {
    Write-Log "EXCEPCIÓN NO CONTROLADA: $_"
    exit 1
}
