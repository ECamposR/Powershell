<#
.SYNOPSIS
Consulta el registro de eventos del Sistema en busca de eventos relacionados con reinicios inesperados y errores críticos.

.DESCRIPTION
Este script busca en el registro de eventos 'System' los siguientes IDs de evento:
- 6008: Indica que el cierre anterior del sistema no fue esperado.
- 1001: Corresponde a un BugCheck (Pantallazo Azul / BSOD), que a menudo causa reinicios. Contiene detalles del error.
- 41 (Fuente: Kernel-Power): Indica que el sistema se reinició sin apagarse limpiamente primero. Esto puede ocurrir por pérdida de energía, un bloqueo total o al mantener presionado el botón de encendido.

El script muestra los eventos encontrados ordenados por fecha (más recientes primero) e incluye información clave.

.NOTES
Se recomienda ejecutar este script con privilegios de Administrador para asegurar el acceso completo a los registros de eventos.
Fecha de creación: 2025-04-23
#>

# --- Inicio del Script ---

Write-Host "Consultando el registro de eventos del Sistema para reinicios inesperados y errores críticos..." -ForegroundColor Yellow

# Definir los IDs de evento a buscar
$EventIDs = @(
    6008, # Cierre inesperado anterior
    1001, # BugCheck (BSOD)
    41    # Kernel-Power (Reinicio sin cierre limpio)
)

# Construir el filtro para Get-WinEvent (más eficiente que filtrar después)
$Filtro = @{
    LogName = 'System'
    ID      = $EventIDs
}

# Obtener los eventos, ordenarlos y manejar errores si no se puede acceder al log
try {
    $EventosEncontrados = Get-WinEvent -FilterHashtable $Filtro -ErrorAction Stop | Sort-Object TimeCreated -Descending
}
catch {
    Write-Error "Error al acceder al registro de eventos 'System'. Asegúrate de ejecutar PowerShell como Administrador."
    # Salir si no se pueden obtener los eventos
    Exit 1
}

# Verificar si se encontraron eventos
if ($EventosEncontrados) {
    Write-Host "Se encontraron los siguientes eventos relevantes (más recientes primero):" -ForegroundColor Green

    # Mostrar los eventos en una tabla formateada
    $EventosEncontrados | Format-Table -AutoSize -Wrap @{Label = 'Fecha y Hora'; Expression = { $_.TimeCreated } },
    @{Label = 'ID Evento'; Expression = { $_.Id } },
    @{Label = 'Fuente'; Expression = { $_.ProviderName } },
    @{Label = 'Nivel'; Expression = { $_.LevelDisplayName } },
    @{Label = 'Mensaje (Inicio)'; Expression = { ($_.Message -split "`r`n?|`n")[0] } } # Muestra solo la primera línea del mensaje

    Write-Host "`nDetalles adicionales:" -ForegroundColor Cyan
    # Mostrar detalles más completos de los eventos de BugCheck (1001) y Kernel-Power (41) si existen
    $EventosCriticosDetalle = $EventosEncontrados | Where-Object { $_.Id -eq 1001 -or $_.Id -eq 41 }
    if ($EventosCriticosDetalle) {
        Write-Host "Detalles de eventos Kernel-Power (ID 41) y BugCheck (ID 1001):"
        $EventosCriticosDetalle | ForEach-Object {
            Write-Host "--- Evento ID $($_.Id) - $($_.TimeCreated) ---" -ForegroundColor Yellow
            # El mensaje completo a menudo tiene más detalles, especialmente para el ID 41 y 1001
            Write-Host $_.Message
            # Para el ID 1001 (BugCheck), los parámetros suelen estar en las propiedades del evento
            if ($_.Id -eq 1001) {
                # Intentar extraer los parámetros del BugCheck del mensaje o propiedades si están disponibles
                # Esto puede variar según la versión de Windows y cómo se registra el evento.
                # Aquí un intento genérico basado en el formato común del mensaje:
                $BugCheckParams = $_.Message -match 'Bugcheck code: (0x[0-9a-fA-F]+)\s*Bugcheck parameters: (0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)'
                if ($Matches) {
                    Write-Host "Bugcheck Code: $($Matches[1])"
                    Write-Host "Parámetros: $($Matches[2]), $($Matches[3]), $($Matches[4]), $($Matches[5])"
                }
                else {
                    # Si no se encuentra en el mensaje, podría estar en las propiedades XML (más complejo de extraer aquí)
                    Write-Host "Parámetros del BugCheck no encontrados fácilmente en el mensaje. Revisa los detalles del evento manualmente."
                }
            }
            Write-Host "--------------------------------------"
        }
    }

}
else {
    Write-Host "No se encontraron eventos recientes con los IDs $EventIDs en el registro del Sistema." -ForegroundColor Green
}

Write-Host "`n--- Fin de la consulta ---" -ForegroundColor Yellow

# --- Fin del Script ---