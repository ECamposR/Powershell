<#
.SYNOPSIS
Busca eventos de Error, Advertencia y Criticos en los registros de Sistema y Aplicacion
en un periodo especifico ANTES de una hora de reinicio conocida.

.DESCRIPTION
Este script ayuda a identificar posibles causas de un reinicio inesperado al
examinar los eventos registrados justo antes de que ocurriera.
Necesitas proporcionar la fecha y hora aproximada del reinicio (obtenida del script anterior).
Busca en los ultimos X minutos antes de esa hora.

.PARAMETER HoraReinicio
La fecha y hora del reinicio inesperado (o el evento 6008/41/1001 asociado).
Formato de ejemplo: "AAAA-MM-DD HH:MM:SS" (ej. "2025-04-23 06:30:00")

.PARAMETER MinutosAntes
Cuantos minutos antes de la HoraReinicio quieres buscar eventos. Por defecto, 30 minutos.

.EXAMPLE
.\AnalizarEventosAntesDeReinicio.ps1 -HoraReinicio "2025-04-23 06:30:00" -MinutosAntes 15

.NOTES
Ejecutar como Administrador. Ajusta el formato de fecha/hora si es necesario.
Version: 1.0 (Sin caracteres especiales)
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$HoraReinicio,

    [Parameter(Mandatory = $false)]
    [int]$MinutosAntes = 30
)

# --- Validacion y Configuracion ---
try {
    # Intentar convertir la cadena de hora a un objeto DateTime
    $TiempoReinicioObj = [datetime]::Parse($HoraReinicio)
}
catch {
    Write-Error "Formato de HoraReinicio invalido. Usa 'AAAA-MM-DD HH:MM:SS'. Ejemplo: '2025-04-23 06:30:00'"
    Exit 1
}

$TiempoInicioBusqueda = $TiempoReinicioObj.AddMinutes(-$MinutosAntes)
$LogsAConsultar = @('System', 'Application')
# Niveles: 1=Critico, 2=Error, 3=Advertencia
$NivelesAIncluir = @(1, 2, 3)

Write-Host "--- Buscando eventos (Critico, Error, Advertencia) en logs [ $LogsAConsultar ] ---" -ForegroundColor Cyan
Write-Host "--- Periodo: Desde $TiempoInicioBusqueda hasta $TiempoReinicioObj ---" -ForegroundColor Cyan

# --- Consulta de Eventos ---
$EventosEncontrados = @() # Inicializar array para acumular eventos

foreach ($log in $LogsAConsultar) {
    Write-Host "Consultando log: $log ..."
    try {
        $Filtro = @{
            LogName   = $log
            StartTime = $TiempoInicioBusqueda
            EndTime   = $TiempoReinicioObj
            Level     = $NivelesAIncluir
        }
        # Acumular eventos encontrados de este log
        $EventosEncontrados += Get-WinEvent -FilterHashtable $Filtro -ErrorAction Stop
    }
    catch {
        Write-Warning "No se pudo consultar el log '$log' o no se encontraron eventos en el periodo. Mensaje: $($_.Exception.Message)"
    }
}

# --- Mostrar Resultados ---
if ($EventosEncontrados.Count -gt 0) {
    Write-Host "`n--- Eventos encontrados ordenados cronologicamente ---" -ForegroundColor Green
    # Ordenar todos los eventos acumulados por fecha/hora
    $EventosEncontrados | Sort-Object TimeCreated | Format-Table TimeCreated, LogName, ProviderName, Id, LevelDisplayName, TaskDisplayName, Message -AutoSize -Wrap
    Write-Host "`nAnaliza estos eventos para ver si algun error o advertencia especifico precede consistentemente los reinicios."
}
else {
    Write-Host "`nNo se encontraron eventos de nivel Critico, Error o Advertencia en los logs [$LogsAConsultar] durante los $MinutosAntes minutos antes de $HoraReinicio." -ForegroundColor Yellow
}

Write-Host "`n--- Fin del analisis de eventos pre-reinicio ---" -ForegroundColor Cyan