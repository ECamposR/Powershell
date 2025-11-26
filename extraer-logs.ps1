<#
.SYNOPSIS
    Script interactivo para exportar eventos de Windows a TXT o JSON,
    filtrando por rango de fechas/horas y opcionalmente por ID de evento.

.NOTAS
    Ejecutar en PowerShell con permisos suficientes para leer el log indicado.
#>

Clear-Host

Write-Host "=== Exportador de logs de eventos de Windows ===`n"

# 1. Selección de log
$logName = Read-Host "Nombre del log a consultar (ej: System, Application, Security) [Default: System]"
if ([string]::IsNullOrWhiteSpace($logName)) {
    $logName = "System"
}

# 2. Rango de fechas/horas
Write-Host "`nIndique el rango de fechas y horas."
Write-Host "Ejemplos típicos válidos (dependen de tu configuración regional):"
Write-Host "  2025-11-26 8:00"
Write-Host "  2025-11-26 08:00"
Write-Host "  26/11/2025 8:00"
$startInput = Read-Host "Fecha/hora de INICIO"
$endInput   = Read-Host "Fecha/hora de FIN"

# Usar Get-Date con try/catch para evitar problemas de sobrecargas de ParseExact
try {
    $startTime = Get-Date -Date $startInput -ErrorAction Stop
} catch {
    Write-Host "ERROR: No se pudo interpretar la fecha/hora de inicio: $($startInput)" -ForegroundColor Red
    Write-Host "Detalle: $($_.Exception.Message)" -ForegroundColor DarkRed
    exit 1
}

try {
    $endTime = Get-Date -Date $endInput -ErrorAction Stop
} catch {
    Write-Host "ERROR: No se pudo interpretar la fecha/hora de fin: $($endInput)" -ForegroundColor Red
    Write-Host "Detalle: $($_.Exception.Message)" -ForegroundColor DarkRed
    exit 1
}

if ($endTime -lt $startTime) {
    Write-Host "ERROR: La fecha/hora de fin es anterior a la de inicio." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Rango interpretado:"
Write-Host "  Inicio : $startTime"
Write-Host "  Fin    : $endTime"

# 3. Tipo de filtro: todos o por ID
Write-Host ""
$filterType = Read-Host "¿Desea obtener (A) TODOS los eventos del rango o (B) filtrar por ID de evento? [A/B]"

$filterType = $filterType.Trim().ToUpper()
$eventIds = $null

switch ($filterType) {
    "B" {
        $idInput = Read-Host "Introduzca uno o varios ID de evento separados por comas (ej: 1006, 4624, 7036)"
        if ([string]::IsNullOrWhiteSpace($idInput)) {
            Write-Host "No se introdujo ningún ID de evento. Se obtendrán todos los eventos." -ForegroundColor Yellow
            $filterType = "A"
        } else {
            try {
                $eventIds = $idInput.Split(",") |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { $_ -ne "" } |
                    ForEach-Object { [int]$_ }
            } catch {
                Write-Host "ERROR: Uno o más ID de evento no son números válidos." -ForegroundColor Red
                exit 1
            }

            if (-not $eventIds -or $eventIds.Count -eq 0) {
                Write-Host "No se pudieron obtener ID de evento válidos. Se obtendrán todos los eventos." -ForegroundColor Yellow
                $filterType = "A"
            }
        }
    }
    default {
        $filterType = "A"
    }
}

# 4. Formato de salida
Write-Host ""
$outFormat = Read-Host "Formato de salida: TXT o JSON? [TXT/JSON]"
$outFormat = $outFormat.Trim().ToUpper()

if ($outFormat -ne "JSON" -and $outFormat -ne "TXT") {
    Write-Host "Formato no reconocido. Se usará TXT por defecto." -ForegroundColor Yellow
    $outFormat = "TXT"
}

# 5. Ruta de salida
$timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$logClean    = ($logName -replace '[^\w\-]', '_')
$defaultName = "Eventos_${logClean}_${timestamp}." + ($outFormat.ToLower())

$defaultPath = Join-Path -Path (Get-Location) -ChildPath $defaultName
Write-Host ""
Write-Host "Ruta por defecto del archivo de salida:"
Write-Host "    $defaultPath"
$outPath = Read-Host "Introduzca la ruta completa del archivo de salida o presione ENTER para usar la ruta por defecto"

if ([string]::IsNullOrWhiteSpace($outPath)) {
    $outPath = $defaultPath
}

# 6. Construir filtro para Get-WinEvent
$filterHash = @{
    LogName   = $logName
    StartTime = $startTime
    EndTime   = $endTime
}

if ($filterType -eq "B" -and $eventIds) {
    $filterHash.Id = $eventIds
}

Write-Host "`nConsultando eventos... Esto puede tardar unos momentos en función del rango y número de eventos."

try {
    $events = Get-WinEvent -FilterHashtable $filterHash -ErrorAction Stop
} catch {
    Write-Host "ERROR al consultar los eventos: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not $events -or $events.Count -eq 0) {
    Write-Host "No se encontraron eventos para los criterios especificados." -ForegroundColor Yellow
    exit 0
}

Write-Host "Se obtuvieron $($events.Count) eventos. Exportando a archivo..."

# 7. Exportar según formato
try {
    if ($outFormat -eq "JSON") {
        # Seleccionar propiedades útiles y convertir a JSON
        $events |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, MachineName, Message |
            ConvertTo-Json -Depth 5 |
            Set-Content -Path $outPath -Encoding UTF8
    } else {
        # Exportar en formato de texto legible
        $events |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, MachineName, Message |
            Format-List * |
            Out-String |
            Set-Content -Path $outPath -Encoding UTF8
    }

    Write-Host "Exportación completada." -ForegroundColor Green
    Write-Host "Archivo generado en:"
    Write-Host "    $outPath"
} catch {
    Write-Host "ERROR al escribir el archivo: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

