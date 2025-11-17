# MonitorDisplay.ps1
# Guarda eventos relacionados con vídeo en un archivo en la carpeta donde se ejecute el script.

# Determinar carpeta de ejecución (funciona si ejecutas .\MonitorDisplay.ps1 o desde el prompt en la carpeta)
if ($PSScriptRoot) {
    $basePath = $PSScriptRoot
} else {
    $basePath = (Get-Location).ProviderPath
}

$logfile = Join-Path $basePath 'monitor_display_log.txt'
"=== Monitor iniciado $(Get-Date -Format o) ===" | Out-File $logfile -Encoding utf8 -Append

$lastTime = Get-Date
try {
    while ($true) {
        $events = Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$lastTime} -ErrorAction SilentlyContinue
        foreach ($e in $events) {
            if ($e.ProviderName -match 'Display|dxg|nvldd|nvlddmkm|nvlddmkm|atikmpag|amdkmdag|amdkmdap|igfx|i915|intel|amd|nvidia|dxgkrnl') {
                $line = "$((Get-Date).ToString('o')) EventID:$($e.Id) Provider:$($e.ProviderName) Message:$($e.Message -replace '\r?\n',' | ')"
                $line | Out-File -FilePath $logfile -Append -Encoding utf8
            }
        }
        $lastTime = Get-Date
        Start-Sleep -Seconds 3
    }
} catch {
    "Monitor detenido por excepción: $_" | Out-File $logfile -Append -Encoding utf8
}

