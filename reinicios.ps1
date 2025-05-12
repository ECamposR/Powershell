<#
.SYNOPSIS
Realiza un diagnostico extendido de reinicios inesperados en Windows, recopilando informacion critica del sistema, eventos, hardware y software.

.DESCRIPTION
Este script mejorado recopila y presenta informacion clave para diagnosticar reinicios inesperados:
1.  Informacion basica del Sistema Operativo y Hardware (Version OS, CPU, RAM Total).
2.  Tiempo de Actividad y Ultimo Arranque del Sistema.
3.  Consulta eventos criticos (IDs 6008, 1001, 41) y Errores/Advertencias recientes en logs de Sistema y Aplicacion.
4.  Busca especificamente errores de Hardware registrados por WHEA-Logger (muy importante).
5.  Verifica la configuracion de volcado de memoria y busca archivos Minidump existentes.
6.  Comprueba el estado de salud (SMART) de los discos fisicos, resaltando advertencias.
7.  Lista los controladores (drivers) de terceros instalados, potenciales causantes de inestabilidad.
8.  Muestra las actualizaciones de Windows instaladas recientemente.
9.  Proporciona un resumen de hallazgos clave y recomendaciones adicionales.

El script utiliza colores para resaltar secciones e informacion importante (Advertencias/Errores).
Se mantienen los mensajes sin tildes ni caracteres especiales para compatibilidad.

.NOTES
Se REQUIERE ejecutar este script con privilegios de Administrador para acceder a toda la informacion.
Fecha de creacion: 2025-05-12
Version: 3.0 (Integracion de multiples chequeos, mejor formato)
Creado por: [Tu Nombre o Alias si deseas]
Inspirado en scripts originales de ECamposR.
#>

# --- Configuracion Inicial ---
$MaxEventosCriticos = 50       # Maximo de eventos criticos (6008, 1001, 41) a mostrar
$MaxOtrosEventos = 25        # Maximo de eventos de Error/Advertencia generales (Sistema/Aplicacion)
$MaxActualizaciones = 15     # Numero de actualizaciones recientes a mostrar
$MaxDriversTerceros = 100    # Maximo de drivers de terceros a listar
$MaxWheaEvents = 50          # Maximo de eventos WHEA a mostrar

# --- Inicio del Script ---
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "=== INICIO: Script de Diagnostico Extendido de Reinicios ($(Get-Date)) ===" -ForegroundColor Magenta
Write-Host "================================================================"

# --- Funcion Auxiliar para Escribir Titulos de Seccion ---
function Write-SectionHeader {
    param(
        [string]$Title,
        [int]$SectionNumber,
        [int]$TotalSections
    )
    Write-Host "`n--- [$SectionNumber/$TotalSections] $Title ---" -ForegroundColor Cyan
}

$TotalSecciones = 9 # Ajustar si anades/quitas secciones

# --- [1/$TotalSecciones] Informacion del Sistema ---
Write-SectionHeader -Title "Informacion del Sistema y Hardware Basico" -SectionNumber 1 -TotalSections $TotalSecciones
try {
    $OSInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $CSInfo = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $CPUInfo = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 # Solo el primer CPU si hay varios
    Write-Host "Sistema Operativo : $($OSInfo.Caption) (Build $($OSInfo.BuildNumber))"
    Write-Host "Arquitectura      : $($OSInfo.OSArchitecture)"
    Write-Host "Version           : $($OSInfo.Version)"
    Write-Host "Fabricante        : $($CSInfo.Manufacturer)"
    Write-Host "Modelo            : $($CSInfo.Model)"
    Write-Host "CPU               : $($CPUInfo.Name)"
    # Usar "{0:N2}" para formatear con 2 decimales y separador de miles segun cultura local
    $TotalRAMGB = [math]::Round($CSInfo.TotalPhysicalMemory / 1GB, 2)
    Write-Host "RAM Total Instalada: $TotalRAMGB GB" # "{0:N2}" quita el 'GB' asi que lo ponemos manualmente
}
catch {
    Write-Warning "No se pudo obtener toda la informacion basica del sistema: $($_.Exception.Message)"
}

# --- [2/$TotalSecciones] Tiempo de Actividad y Ultimo Arranque ---
Write-SectionHeader -Title "Tiempo de Actividad del Sistema" -SectionNumber 2 -TotalSections $TotalSecciones
try {
    # OSInfo ya obtenido arriba si no fallo
    if ($OSInfo) {
        $UltimoArranque = $OSInfo.LastBootUpTime
        $TiempoActivo = New-TimeSpan -Start $UltimoArranque -End (Get-Date)
        # Usar "Ultimo arranque" sin tilde
        Write-Host "Ultimo arranque del sistema : $UltimoArranque"
        Write-Host "Tiempo activo desde entonces: $($TiempoActivo.Days) dias, $($TiempoActivo.Hours) horas, $($TiempoActivo.Minutes) minutos"
    }
    else {
        Write-Warning "Informacion de tiempo de actividad no disponible (fallo obtener OSInfo)."
    }
}
catch {
    # Usar "informacion" sin tilde
    Write-Warning "No se pudo obtener la informacion de tiempo de actividad: $($_.Exception.Message)"
}

# --- [3/$TotalSecciones] Eventos Criticos, Errores y Advertencias (Sistema y Aplicacion) ---
Write-SectionHeader -Title "Eventos Relevantes (Sistema y Aplicacion)" -SectionNumber 3 -TotalSections $TotalSecciones

$EventosHallados = @() # Array para acumular todos los eventos relevantes

# 3.1 Eventos Criticos Especificos (6008, 1001, 41) del log de Sistema
Write-Host "Consultando eventos criticos especificos (IDs 6008, 1001, 41) en 'System'..." -ForegroundColor Yellow
$EventIDsCriticos = @(6008, 1001, 41)
$FiltroEventosCriticos = @{ LogName = 'System'; ID = $EventIDsCriticos }
try {
    $EventosCriticos = Get-WinEvent -FilterHashtable $FiltroEventosCriticos -MaxEvents $MaxEventosCriticos -ErrorAction Stop | Sort-Object TimeCreated -Descending
    if ($EventosCriticos) {
        Write-Host "Se encontraron los siguientes eventos criticos (max $MaxEventosCriticos, mas recientes primero):" -ForegroundColor Green
        $EventosCriticos | Format-Table -AutoSize -Wrap @{Label = 'Fecha y Hora'; Expression = { $_.TimeCreated } },
        @{Label = 'ID Evento'; Expression = { $_.Id } },
        @{Label = 'Fuente'; Expression = { $_.ProviderName } },
        @{Label = 'Nivel'; Expression = { $_.LevelDisplayName } },
        @{Label = 'Mensaje (Inicio)'; Expression = { ($_.Message -split "`r`n?|`n")[0] } } # Primera linea
        $EventosHallados += $EventosCriticos # Acumular para analisis posterior

        # Mostrar detalles adicionales para eventos 1001 y 41
        $EventosConDetalle = $EventosCriticos | Where-Object { $_.Id -in (1001, 41) }
        if ($EventosConDetalle) {
            Write-Host "`nDetalles adicionales para eventos ID 1001 (BugCheck/BSOD) y 41 (Kernel-Power):" -ForegroundColor Yellow
            # (Mismo codigo de extraccion de detalles que el script original)
            $EventosConDetalle | ForEach-Object {
                Write-Host "--- Evento ID $($_.Id) - $($_.TimeCreated) ---"
                #Write-Host "$($_.Message)" # Mensaje completo puede ser muy largo, el inicio ya esta en la tabla
                if ($_.Id -eq 1001) {
                    $BugCheckParams = $_.Message -match 'Bugcheck code: (0x[0-9a-fA-F]+)\s*Bugcheck parameters: (0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)'
                    if ($Matches) {
                        Write-Host "-> Bugcheck Code: $($Matches[1])" -ForegroundColor Red
                        Write-Host "-> Parametros: $($Matches[2]), $($Matches[3]), $($Matches[4]), $($Matches[5])"
                        Write-Host "(Busca este codigo de error online para posibles causas)"
                    }
                    else { Write-Host "(No se pudieron extraer parametros de BugCheck del mensaje)" }
                }
                if ($_.Id -eq 41) {
                    try {
                        $XmlEvent = [xml]$_.ToXml()
                        $BugcheckCode = $XmlEvent.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckCode' } | Select-Object -ExpandProperty '#text'
                        $PowerButtonTimestamp = $XmlEvent.Event.EventData.Data | Where-Object { $_.Name -eq 'PowerButtonTimestamp' } | Select-Object -ExpandProperty '#text'
                        if ($BugcheckCode -ne '0') { Write-Host "-> BugcheckCode (desde datos evento 41): $BugcheckCode" -ForegroundColor Red }
                        if ($PowerButtonTimestamp -ne '0') { Write-Host "-> PowerButtonTimestamp (indica uso del boton de encendido): $PowerButtonTimestamp" }
                        if ($BugcheckCode -eq '0' -and $PowerButtonTimestamp -eq '0') { Write-Host "(Evento 41 sin codigo de error especifico, puede ser perdida de energia o forzado)" }
                    }
                    catch { Write-Warning "No se pudo procesar el XML del evento ID 41: $($_.Exception.Message)" }
                }
                Write-Host "--------------------------------------"
            }
        }
    }
    else { Write-Host "No se encontraron eventos criticos recientes (IDs $EventIDsCriticos) en el registro 'System'." -ForegroundColor Green }
}
catch { Write-Error "Error al acceder a eventos criticos del registro 'System'. Asegurate de ejecutar como Administrador. Seccion omitida." }

# 3.2 Eventos de Error y Advertencia recientes en 'System' y 'Application'
Write-Host "`nConsultando ultimos Errores/Advertencias en logs 'System' y 'Application'..." -ForegroundColor Yellow
$LogsGenerales = @('System', 'Application')
$NivelesErrorWarn = @(1, 2, 3) # 1=Critico, 2=Error, 3=Advertencia
foreach ($log in $LogsGenerales) {
    $FiltroEventosGenerales = @{ LogName = $log; Level = $NivelesErrorWarn }
    try {
        $EventosLog = Get-WinEvent -FilterHashtable $FiltroEventosGenerales -MaxEvents $MaxOtrosEventos -ErrorAction Stop | Sort-Object TimeCreated -Descending
        if ($EventosLog) {
            Write-Host "Ultimos Errores/Advertencias encontrados en '$log' (max $MaxOtrosEventos):" -ForegroundColor Green
            $EventosLog | Format-Table -AutoSize -Wrap @{Label = 'Fecha y Hora'; Expression = { $_.TimeCreated } },
            @{Label = 'ID Evento'; Expression = { $_.Id } },
            @{Label = 'Fuente'; Expression = { $_.ProviderName } },
            @{Label = 'Nivel'; Expression = { $_.LevelDisplayName } },
            @{Label = 'Mensaje (Inicio)'; Expression = { ($_.Message -split "`r`n?|`n")[0] } }
            $EventosHallados += $EventosLog # Acumular
        }
        else { Write-Host "No se encontraron Errores/Advertencias recientes en el log '$log'." -ForegroundColor Green }
    }
    catch { Write-Warning "Error consultando log '$log' para Errores/Advertencias: $($_.Exception.Message)" }
}

# --- [4/$TotalSecciones] Errores de Hardware (WHEA-Logger) ---
Write-SectionHeader -Title "Errores de Hardware Registrados (WHEA-Logger)" -SectionNumber 4 -TotalSections $TotalSecciones
$ProviderNameWHEA = "Microsoft-Windows-WHEA-Logger"
$WheaEventsFound = $false
try {
    $WheaEvents = Get-WinEvent -ProviderName $ProviderNameWHEA -MaxEvents $MaxWheaEvents -ErrorAction Stop | Sort-Object TimeCreated -Descending
    if ($WheaEvents) {
        Write-Warning "*** ¡ALERTA! Se encontraron eventos de WHEA-Logger. Esto indica posibles problemas de HARDWARE. ***"
        Write-Host "Mostrando los ultimos $MaxWheaEvents eventos encontrados (mas recientes primero):"
        $WheaEvents | Format-Table TimeCreated, Id, LevelDisplayName, Message -AutoSize -Wrap
        Write-Host "`nInvestiga los detalles de estos errores (CPU, RAM, PCIe, etc.). Busca 'ErrorSource' en los mensajes." -ForegroundColor Yellow
        $WheaEventsFound = $true
        $EventosHallados += $WheaEvents # Acumular
    }
    else { Write-Host "No se encontraron eventos recientes de WHEA-Logger en el registro del Sistema." -ForegroundColor Green }
}
catch {
    if ($_.Exception.Message -like "*No events were found*") {
        Write-Host "No se encontraron eventos de WHEA-Logger en el registro del Sistema." -ForegroundColor Green
    }
    else { Write-Warning "Error al consultar eventos de WHEA-Logger: $($_.Exception.Message)" }
}

# --- [5/$TotalSecciones] Configuracion y Archivos de Volcado de Memoria ---
Write-SectionHeader -Title "Archivos y Configuracion de Volcado de Memoria (Minidump)" -SectionNumber 5 -TotalSections $TotalSecciones
# 5.1 Verificar configuracion
Write-Host "Verificando configuracion de volcado de memoria..."
try {
    $DumpConfig = Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\CrashControl" -ErrorAction Stop
    $DumpType = $DumpConfig.CrashDumpEnabled
    $DumpFile = $DumpConfig.DumpFile
    $MiniDumpDir = $DumpConfig.MinidumpDir
    $Overwrite = $DumpConfig.Overwrite

    $DumpTypeText = switch ($DumpType) {
        0 { "Ninguno (Deshabilitado)" }
        1 { "Volcado de memoria completo" }
        2 { "Volcado de memoria del nucleo" }
        3 { "Volcado de memoria pequeno (Minidump)" }
        7 { "Volcado automatico de memoria" }
        default { "Desconocido ($DumpType)" }
    }

    Write-Host "Tipo de volcado configurado: $DumpTypeText" -ForegroundColor Green
    if ($DumpType -eq 0) {
        Write-Warning "La creacion de volcados de memoria esta deshabilitada. Se recomienda habilitar 'Volcado automatico' o 'Minidump' para diagnosticar BSODs."
    }
    else {
        if ($DumpType -in (1, 2)) { Write-Host "Ubicacion archivo volcado : $DumpFile" }
        if ($DumpType -in (3, 7)) { Write-Host "Directorio Minidump       : $MiniDumpDir" }
        Write-Host "Sobrescribir archivo existente: $($Overwrite -eq 1)"
    }

}
catch {
    Write-Warning "No se pudo verificar la configuracion de volcado de memoria: $($_.Exception.Message)"
    $MiniDumpDir = "$env:SystemRoot\Minidump" # Asumir default si falla lectura de registro
    Write-Host "Asumiendo directorio Minidump por defecto: $MiniDumpDir" -ForegroundColor Yellow
}

# 5.2 Buscar archivos Minidump
Write-Host "`nBuscando archivos *.dmp existentes..."
$RutaMinidump = if ($MiniDumpDir) { $MiniDumpDir } else { "$env:SystemRoot\Minidump" } # Usar el directorio leido o el default
$MinidumpsFound = $false
if (Test-Path $RutaMinidump) {
    try {
        $Minidumps = Get-ChildItem -Path $RutaMinidump -Filter *.dmp -File -ErrorAction Stop | Sort-Object LastWriteTime -Descending
        if ($Minidumps) {
            Write-Host "Se encontraron los siguientes archivos Minidump (utiles para analizar BSODs):" -ForegroundColor Green
            $Minidumps | Select-Object Name, @{Name = 'Fecha Creacion'; Expression = { $_.LastWriteTime } }, @{Name = 'Tamano (MB)'; Expression = { [math]::Round($_.Length / 1MB, 2) } } | Format-Table -AutoSize
            Write-Host "Analiza estos archivos con 'WinDbg Preview' (de la Microsoft Store) para obtener detalles del error."
            $MinidumpsFound = $true
        }
        else { Write-Host "No se encontraron archivos .dmp en la carpeta '$RutaMinidump'." -ForegroundColor Green }
    }
    catch { Write-Warning "Error al buscar Minidumps en '$RutaMinidump': $($_.Exception.Message)" }
}
else { Write-Host "La carpeta Minidump ($RutaMinidump) no existe o no se pudo determinar." }

# --- [6/$TotalSecciones] Estado de Salud de Discos Fisicos ---
Write-SectionHeader -Title "Estado de Salud de Discos Fisicos (SMART)" -SectionNumber 6 -TotalSections $TotalSecciones
$DiskWarning = $false
try {
    $Discos = Get-PhysicalDisk -ErrorAction Stop
    if ($Discos) {
        Write-Host "Estado reportado por los discos fisicos:" -ForegroundColor Green
        $Discos | Select-Object DeviceID, FriendlyName, MediaType, @{Name = 'Tamano (GB)'; Expression = { [math]::Round($_.Size / 1GB, 1) } }, HealthStatus, OperationalStatus | Format-Table -AutoSize
        Write-Host "Leyenda: HealthStatus ('Healthy', 'Warning', 'Unhealthy'), OperationalStatus (indica si esta funcionando correctamente)."
        $DiscosProblematicos = $Discos | Where-Object { $_.HealthStatus -ne 'Healthy' -or $_.OperationalStatus -ne 'OK' }
        if ($DiscosProblematicos) {
            Write-Warning "¡Atencion! Uno o mas discos reportan un estado de salud diferente a 'Healthy' o un estado operacional diferente a 'OK'."
            $DiskWarning = $true
        }
    }
    else { Write-Host "No se detectaron discos fisicos a traves de Get-PhysicalDisk." }
}
catch { Write-Warning "No se pudo obtener la informacion de los discos fisicos: $($_.Exception.Message)" }

# --- [7/$TotalSecciones] Drivers de Terceros (No-Microsoft) ---
Write-SectionHeader -Title "Controladores (Drivers) de Terceros Instalados" -SectionNumber 7 -TotalSections $TotalSecciones
$DriversTercerosEncontrados = $false
try {
    # Usar Win32_PnPSignedDriver para obtener mas detalles como fecha/version
    $Drivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object { $_.Manufacturer -ne "Microsoft" -and $_.Manufacturer -notlike "*Microsoft*" } | Select-Object DeviceName, Manufacturer, DriverVersion, @{Name = 'Fecha Driver'; Expression = { $_.DriverDate } } | Sort-Object Manufacturer, DeviceName | Select-Object -First $MaxDriversTerceros

    if ($Drivers) {
        Write-Host "Se encontraron los siguientes drivers firmados de terceros (max $MaxDriversTerceros):" -ForegroundColor Green
        $Drivers | Format-Table -AutoSize -Wrap
        Write-Host "`nRevisa si drivers criticos (Graficos, Red, Chipset, Audio) se actualizaron justo antes de los problemas." -ForegroundColor Yellow
        Write-Host "Considera actualizarlos desde la web del fabricante del PC o del componente."
        $DriversTercerosEncontrados = $true
    }
    else {
        Write-Host "No se encontraron drivers firmados de terceros usando Win32_PnPSignedDriver." -ForegroundColor Yellow
        # Intentar metodo alternativo (puede incluir no firmados)
        Write-Host "Intentando con Get-WindowsDriver..."
        $DriversAlt = Get-WindowsDriver -Online -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -ne 'Microsoft' } | Select-Object ClassName, ProviderName, Date, Version | Sort-Object ProviderName, ClassName | Select-Object -First $MaxDriversTerceros
        if ($DriversAlt) {
            Write-Host "Drivers encontrados con Get-WindowsDriver (puede incluir no firmados, max $MaxDriversTerceros):" -ForegroundColor Green
            $DriversAlt | Format-Table -AutoSize -Wrap
            $DriversTercerosEncontrados = $true
        }
        else { Write-Host "Tampoco se encontraron drivers de terceros con Get-WindowsDriver." -ForegroundColor Yellow }
    }
}
catch { Write-Warning "Error al obtener la lista de drivers: $($_.Exception.Message)" }

# --- [8/$TotalSecciones] Ultimas Actualizaciones de Windows Instaladas ---
Write-SectionHeader -Title "Ultimas Actualizaciones de Windows Instaladas (KB)" -SectionNumber 8 -TotalSections $TotalSecciones
try {
    $Actualizaciones = Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First $MaxActualizaciones
    if ($Actualizaciones) {
        Write-Host "Mostrando las ultimas $MaxActualizaciones instaladas:" -ForegroundColor Green
        $Actualizaciones | Format-Table HotFixID, Description, InstalledOn -AutoSize -Wrap
        Write-Host "`nComprueba si los reinicios comenzaron poco despues de instalar alguna actualizacion reciente." -ForegroundColor Yellow
    }
    else { Write-Host "No se encontraron actualizaciones (HotFix) recientes." -ForegroundColor Green }
}
catch { Write-Warning "No se pudo obtener la informacion de las actualizaciones: $($_.Exception.Message)" }

# --- [9/$TotalSecciones] Resumen y Pasos Adicionales Recomendados ---
Write-SectionHeader -Title "Resumen de Hallazgos Clave y Pasos Siguientes" -SectionNumber 9 -TotalSections $TotalSecciones

Write-Host "Resumen de posibles problemas detectados por el script:" -ForegroundColor Yellow
$ProblemasDetectados = $false
if ($EventosHallados | Where-Object { $_.Id -in (1001, 41, 6008) }) {
    Write-Host "- Se detectaron eventos criticos relacionados con reinicios/BSOD (IDs 1001, 41, 6008)." -ForegroundColor Red
    $ProblemasDetectados = $true
}
if ($WheaEventsFound) {
    Write-Host "- ¡Se detectaron errores de hardware WHEA! Investigar urgentemente." -ForegroundColor Red
    $ProblemasDetectados = $true
}
if ($MinidumpsFound) {
    Write-Host "- Se encontraron archivos Minidump. Analizalos con WinDbg." -ForegroundColor Yellow
    $ProblemasDetectados = $true
}
if ($DiskWarning) {
    Write-Host "- ¡Advertencia en el estado de salud de uno o mas discos!" -ForegroundColor Red
    $ProblemasDetectados = $true
}
if (!($EventosHallados | Where-Object { $_.Id -in (1001, 41, 6008) }) -and !$WheaEventsFound -and !$DiskWarning) {
    Write-Host "- No se detectaron señales obvias de BSOD, errores WHEA o problemas de disco en este analisis." -ForegroundColor Green
    Write-Host "  Considera causas relacionadas con software, drivers (revisa lista), sobrecalentamiento o fuente de poder."
}

Write-Host "`nPasos Adicionales Recomendados (Manuales):" -ForegroundColor Yellow
Write-Host "- Revisa el 'Monitor de Fiabilidad': Busca 'Reliability History' en Windows o ejecuta 'perfmon /rel'. Vista grafica de errores."
Write-Host "- Ejecuta 'Diagnostico de memoria de Windows': Busca la herramienta para comprobar RAM (requiere reiniciar)."
Write-Host "- Monitoriza Temperaturas (CPU/GPU): Usa HWMonitor, HWiNFO o similar, especialmente bajo carga (jugando, trabajando)."
Write-Host "- Comprueba Archivos del Sistema: Abre CMD/PowerShell como Admin y ejecuta 'sfc /scannow'. Si encuentra errores, luego ejecuta 'DISM /Online /Cleanup-Image /RestoreHealth'."
Write-Host "- Comprueba el Sistema de Archivos del Disco: Abre CMD/PowerShell como Admin y ejecuta 'chkdsk C: /f' (u otra letra). Requiere reiniciar."
Write-Host "- Revisa la Fuente de Poder (PSU): Si es posible, prueba con otra fuente, especialmente si los reinicios ocurren bajo carga."
Write-Host "- Analiza los Minidumps (si existen): Usa WinDbg Preview para obtener detalles especificos del error BSOD."

Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "=== FIN: Script de Diagnostico Extendido ($(Get-Date)) ===" -ForegroundColor Magenta
Write-Host "============================================================"