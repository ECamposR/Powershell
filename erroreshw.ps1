<#
.SYNOPSIS
Busca eventos especificos de errores de hardware registrados por WHEA-Logger.

.DESCRIPTION
Consulta el registro del Sistema buscando eventos de la fuente 'Microsoft-Windows-WHEA-Logger',
los cuales indican problemas de hardware detectados por el sistema operativo.

.NOTES
Ejecutar como Administrador. La presencia de estos errores es significativa.
Version: 1.0 (Sin caracteres especiales)
#>

Write-Host "--- Buscando Errores de Hardware Registrados (WHEA-Logger) ---" -ForegroundColor Cyan

$ProviderName = "Microsoft-Windows-WHEA-Logger"
$MaxWheaEvents = 50 # Limitar por si hay muchos

try {
    $WheaEvents = Get-WinEvent -ProviderName $ProviderName -MaxEvents $MaxWheaEvents -ErrorAction Stop | Sort-Object TimeCreated -Descending

    if ($WheaEvents) {
        Write-Warning "*** ¡Se encontraron eventos de WHEA-Logger! Esto sugiere un posible problema de HARDWARE. ***"
        Write-Host "Mostrando los ultimos $MaxWheaEvents eventos encontrados (mas recientes primero):"
        $WheaEvents | Format-Table TimeCreated, Id, LevelDisplayName, Message -AutoSize -Wrap
        Write-Host "`nInvestiga los detalles de estos errores. Pueden indicar problemas con CPU, RAM, PCIe, etc."
        Write-Host "Busca el 'ErrorSource' y otros detalles dentro del mensaje de cada evento."
    }
    else {
        Write-Host "No se encontraron eventos recientes de WHEA-Logger en el registro del Sistema." -ForegroundColor Green
    }
}
catch {
    # Capturar el error especifico si el proveedor no existe o no hay eventos
    if ($_.Exception.Message -like "*No events were found that match the specified selection criteria*") {
        Write-Host "No se encontraron eventos de WHEA-Logger en el registro del Sistema." -ForegroundColor Green
    }
    else {
        Write-Warning "Error al consultar eventos de WHEA-Logger: $($_.Exception.Message)"
    }
}

Write-Host "`n--- Fin de la busqueda de errores WHEA ---" -ForegroundColor Cyan