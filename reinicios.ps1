<#
.SYNOPSIS
Realiza un diagnostico inicial de reinicios inesperados en Windows.

.DESCRIPTION
Este script recopila informacion clave para ayudar a diagnosticar reinicios inesperados:
1.  Consulta eventos criticos del sistema (IDs 6008, 1001, 41) relacionados con cierres/reinicios inesperados y BSODs.
2.  Muestra el tiempo de actividad del sistema desde el ultimo arranque.
3.  Busca archivos de volcado de memoria (Minidumps) generados durante errores graves (BSOD).
4.  Comprueba el estado de salud basico (SMART) de los discos fisicos.
5.  Lista las actualizaciones de Windows instaladas recientemente.

El script presenta la informacion en secciones separadas para facilitar la lectura.
Se han eliminado tildes y caracteres especiales de los mensajes del script para mejorar la compatibilidad.

.NOTES
Se recomienda encarecidamente ejecutar este script con privilegios de Administrador para asegurar el acceso completo a toda la informacion requerida (registros de eventos, discos, etc.).
Fecha de creacion: 2025-04-23
Version: 2.1 (Sin caracteres especiales en salida de script)
#>

# --- Configuracion Inicial ---
# Numero maximo de eventos a mostrar (para evitar salidas muy largas)
$MaxEventos = 50
# Numero de actualizaciones recientes a mostrar
$MaxActualizaciones = 15

# --- Inicio del Script ---
Write-Host "=== INICIO: Script de Diagnostico de Reinicios Inesperados ===" -ForegroundColor Magenta

# --- Seccion 1: Eventos Criticos del Sistema ---
Write-Host "`n--- [1/5] Consultando Eventos Criticos del Sistema (IDs 6008, 1001, 41) ---" -ForegroundColor Cyan

$EventIDsCriticos = @(6008, 1001, 41)
$FiltroEventos = @{
    LogName = 'System'
    ID      = $EventIDsCriticos
}

try {
    # Obtener eventos, limitar cantidad, ordenar y manejar errores
    $EventosCriticos = Get-WinEvent -FilterHashtable $FiltroEventos -MaxEvents $MaxEventos -ErrorAction Stop | Sort-Object TimeCreated -Descending
}
catch {
    Write-Error "Error al acceder al registro de eventos 'System'. Asegurate de ejecutar PowerShell como Administrador. Seccion omitida."
    # Establecer la variable a null para que las comprobaciones posteriores no fallen
    $EventosCriticos = $null
}

if ($EventosCriticos) {
    Write-Host "Se encontraron los siguientes eventos relevantes (mostrando hasta $MaxEventos, mas recientes primero):" -ForegroundColor Green
    # Usar etiquetas sin tildes
    $EventosCriticos | Format-Table -AutoSize -Wrap @{Label = 'Fecha y Hora'; Expression = { $_.TimeCreated } },
    @{Label = 'ID Evento'; Expression = { $_.Id } },
    @{Label = 'Fuente'; Expression = { $_.ProviderName } },
    @{Label = 'Nivel'; Expression = { $_.LevelDisplayName } },
    @{Label = 'Mensaje (Inicio)'; Expression = { ($_.Message -split "`r`n?|`n")[0] } } # Primera linea del mensaje

    # Mostrar detalles adicionales para eventos 1001 (BSOD) y 41 (Kernel-Power) si existen entre los encontrados
    $EventosConDetalle = $EventosCriticos | Where-Object { $_.Id -in (1001, 41) }
    if ($EventosConDetalle) {
        Write-Host "`nDetalles adicionales para eventos ID 1001 (BugCheck/BSOD) y 41 (Kernel-Power):" -ForegroundColor Yellow
        $EventosConDetalle | ForEach-Object {
            Write-Host "--- Evento ID $($_.Id) - $($_.TimeCreated) ---"
            Write-Host "$($_.Message)" # El mensaje original del sistema puede contener caracteres especiales
            # Intentar extraer parametros de BugCheck para ID 1001
            if ($_.Id -eq 1001) {
                # La expresion regular no usa tildes
                $BugCheckParams = $_.Message -match 'Bugcheck code: (0x[0-9a-fA-F]+)\s*Bugcheck parameters: (0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)'
                if ($Matches) {
                    Write-Host "-> Bugcheck Code: $($Matches[1])"
                    # Usar "Parametros" sin tilde
                    Write-Host "-> Parametros: $($Matches[2]), $($Matches[3]), $($Matches[4]), $($Matches[5])"
                    # Usar "codigo" sin tilde
                    Write-Host "(Busca este codigo de error online para posibles causas)"
                }
            }
            # Para ID 41, buscar BugcheckCode y PowerButtonTimestamp si estan presentes
            if ($_.Id -eq 41) {
                try {
                    $XmlEvent = [xml]$_.ToXml()
                    $BugcheckCode = $XmlEvent.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckCode' } | Select-Object -ExpandProperty '#text'
                    $PowerButtonTimestamp = $XmlEvent.Event.EventData.Data | Where-Object { $_.Name -eq 'PowerButtonTimestamp' } | Select-Object -ExpandProperty '#text'
                    if ($BugcheckCode -ne '0') { Write-Host "-> BugcheckCode (desde datos evento 41): $BugcheckCode" }
                    # Usar "boton" sin tilde
                    if ($PowerButtonTimestamp -ne '0') { Write-Host "-> PowerButtonTimestamp (indica uso del boton de encendido): $PowerButtonTimestamp" }
                }
                catch {
                    Write-Warning "No se pudo procesar el XML del evento ID 41: $($_.Exception.Message)"
                }
            }
            Write-Host "--------------------------------------"
        }
    }

}
elseif ($null -ne $EventosCriticos) {
    # Solo si no hubo error al obtenerlos
    # Usar "registro" sin tilde
    Write-Host "No se encontraron eventos criticos recientes (IDs $EventIDsCriticos) en el registro del Sistema." -ForegroundColor Green
}

# --- Seccion 2: Tiempo de Actividad del Sistema ---
Write-Host "`n--- [2/5] Tiempo de Actividad del Sistema ---" -ForegroundColor Cyan
try {
    $OSInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $UltimoArranque = $OSInfo.LastBootUpTime
    $TiempoActivo = New-TimeSpan -Start $UltimoArranque -End (Get-Date)
    # Usar "Ultimo arranque" sin tilde
    Write-Host "Ultimo arranque del sistema : $UltimoArranque"
    Write-Host "Tiempo activo desde entonces: $($TiempoActivo.Days) dias, $($TiempoActivo.Hours) horas, $($TiempoActivo.Minutes) minutos"
}
catch {
    # Usar "informacion" sin tilde
    Write-Warning "No se pudo obtener la informacion de tiempo de actividad: $($_.Exception.Message)"
}

# --- Seccion 3: Archivos de Volcado de Memoria (Minidump) ---
# Usar "Memoria" sin tilde
Write-Host "`n--- [3/5] Archivos de Volcado de Memoria (Minidump) ---" -ForegroundColor Cyan
$RutaMinidump = "$env:SystemRoot\Minidump"
Write-Host "Buscando archivos *.dmp en: $RutaMinidump"
if (Test-Path $RutaMinidump) {
    # Usar -ErrorAction SilentlyContinue por si hay problemas de permisos con algun archivo especifico
    $Minidumps = Get-ChildItem -Path $RutaMinidump -Filter *.dmp -ErrorAction SilentlyContinue
    if ($Minidumps) {
        # Usar "utiles" sin tilde
        Write-Host "Se encontraron los siguientes archivos Minidump (utiles para analizar BSODs):" -ForegroundColor Green
        # Usar etiquetas sin tildes
        $Minidumps | Select-Object Name, @{Name = 'Fecha Creacion'; Expression = { $_.LastWriteTime } }, @{Name = 'Tamano (MB)'; Expression = { [math]::Round($_.Length / 1MB, 2) } } | Sort-Object 'Fecha Creacion' -Descending | Format-Table -AutoSize
        Write-Host "Analiza estos archivos con 'WinDbg Preview' (de la Microsoft Store) para obtener detalles del error."
    }
    else {
        Write-Host "No se encontraron archivos .dmp en la carpeta Minidump." -ForegroundColor Green
    }
}
else {
    Write-Host "La carpeta Minidump ($RutaMinidump) no existe."
}

# --- Seccion 4: Estado de Salud de Discos Fisicos ---
# Usar "Fisicos" sin tilde
Write-Host "`n--- [4/5] Estado de Salud de Discos Fisicos (SMART) ---" -ForegroundColor Cyan
try {
    # Obtener informacion de discos fisicos
    $Discos = Get-PhysicalDisk -ErrorAction Stop
    if ($Discos) {
        # Usar "fisicos" sin tilde
        Write-Host "Estado reportado por los discos fisicos:" -ForegroundColor Green
        # Usar "Tamano" sin tilde
        $Discos | Select-Object DeviceID, FriendlyName, MediaType, @{Name = 'Tamano (GB)'; Expression = { [math]::Round($_.Size / 1GB, 1) } }, HealthStatus, OperationalStatus | Format-Table -AutoSize
        # Usar "esta funcionando" sin tilde
        Write-Host "Leyenda: HealthStatus ('Healthy', 'Warning', 'Unhealthy'), OperationalStatus (indica si esta funcionando correctamente)."
        if ($Discos | Where-Object { $_.HealthStatus -ne 'Healthy' }) {
            # Usar "Atencion" sin tilde
            Write-Warning "Atencion! Uno o mas discos reportan un estado de salud diferente a 'Healthy'."
        }
    }
    else {
        # Usar "fisicos" sin tilde
        Write-Host "No se detectaron discos fisicos a traves de Get-PhysicalDisk."
    }
}
catch {
    # Usar "informacion" y "fisicos" sin tildes
    Write-Warning "No se pudo obtener la informacion de los discos fisicos: $($_.Exception.Message)"
}

# --- Seccion 5: Ultimas Actualizaciones de Windows Instaladas ---
# Usar "Ultimas" e "Instaladas" sin tildes
Write-Host "`n--- [5/5] Ultimas Actualizaciones de Windows Instaladas (KB) ---" -ForegroundColor Cyan
try {
    # Obtener actualizaciones, ordenar y limitar cantidad
    $Actualizaciones = Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First $MaxActualizaciones
    if ($Actualizaciones) {
        # Usar "Ultimas" e "instaladas" sin tildes
        Write-Host "Mostrando las ultimas $MaxActualizaciones instaladas:" -ForegroundColor Green
        $Actualizaciones | Format-Table HotFixID, Description, InstalledOn -AutoSize -Wrap # La Descripcion viene del sistema y puede tener caracteres especiales
        # Usar "despues" y "actualizacion" sin tildes
        Write-Host "Comprueba si los reinicios inesperados comenzaron poco despues de instalar alguna actualizacion."
    }
    else {
        # Usar "actualizaciones" sin tilde
        Write-Host "No se encontraron actualizaciones (HotFix) recientes." -ForegroundColor Green
    }
}
catch {
    # Usar "informacion" y "actualizaciones" sin tildes
    Write-Warning "No se pudo obtener la informacion de las actualizaciones: $($_.Exception.Message)"
}

# --- Pasos Adicionales Sugeridos (Manuales) ---
Write-Host "`n--- Pasos Adicionales Recomendados (Manuales) ---" -ForegroundColor Yellow
# Usar "Fiabilidad", "grafica" sin tildes
Write-Host "- Revisa el 'Monitor de Fiabilidad': Busca 'Reliability History' en Windows o ejecuta 'perfmon /rel'. Ofrece una vista grafica de errores y cambios."
# Usar "Diagnostico" sin tilde
Write-Host "- Ejecuta 'Diagnostico de memoria de Windows': Busca la herramienta en el menu Inicio para comprobar la RAM (requiere reiniciar)."
Write-Host "- Monitoriza las Temperaturas: Usa software como HWMonitor o HWiNFO para verificar si CPU/GPU se sobrecalientan, especialmente bajo carga."
# Usar "Sistema", "Archivos", "requiera" sin tildes
Write-Host "- Comprueba el Sistema de Archivos: Abre CMD o PowerShell como Admin y ejecuta 'chkdsk C: /f' (u otra letra de unidad). Probablemente requiera reiniciar."

# Usar "Diagnostico" sin tilde
Write-Host "`n=== FIN: Script de Diagnostico ===" -ForegroundColor Magenta