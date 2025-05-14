<#
.SYNOPSIS
    Script de Diagnóstico de Rendimiento Avanzado para Windows.
.DESCRIPTION
    Este script recopila métricas clave del sistema para ayudar a diagnosticar problemas de rendimiento
    en un PC con Windows. Incluye información sobre CPU, RAM, disco (espacio y rendimiento),
    procesos principales, eventos del sistema, programas de inicio y salud del disco.

    IMPORTANTE: Para obtener la información más completa (especialmente S.M.A.R.T. y algunos contadores de rendimiento),
    se recomienda ejecutar este script con privilegios de Administrador.
.VERSION
    2.0
.AUTHOR
    Asistente IA (Basado en solicitud y colaboración)
.DATE
    2025-05-14
.NOTES
    Modo de uso:
    1. Guarde este código como un archivo .ps1 (ej: DiagnosticoRendimientoAvanzado.ps1).
    2. Abra PowerShell (preferiblemente como Administrador).
    3. Navegue al directorio donde guardó el archivo.
    4. Ejecute el script: .\DiagnosticoRendimientoAvanzado.ps1
    5. Para guardar la salida en un archivo: .\DiagnosticoRendimientoAvanzado.ps1 | Out-File -FilePath ".\InformeRendimiento-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
#>

#region Encabezado e Información Inicial
Write-Host "===== INFORME DE RENDIMIENTO AVANZADO DEL SISTEMA =====" -ForegroundColor Yellow
Write-Host "`nFecha y Hora del Informe: $(Get-Date)"
Write-Host "Ejecutando como usuario: $env:USERNAME"
$Global:isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "Ejecutando con privilegios de Administrador: $Global:isAdmin"
if (-not $Global:isAdmin) {
    Write-Warning "Algunas comprobaciones (como S.M.A.R.T. detallado y ciertos contadores) pueden requerir privilegios de Administrador para funcionar completamente."
}
Write-Host "----------------------------------------------------`n"
#endregion

#region Información General del Sistema
Write-Host "===== INFORMACIÓN GENERAL DEL SISTEMA =====" -ForegroundColor Cyan
try {
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $csInfo = Get-CimInstance Win32_ComputerSystem
    Write-Host "Nombre del Equipo: $($csInfo.Name)"
    Write-Host "Sistema Operativo: $($osInfo.Caption), Versión: $($osInfo.Version), Build: $($osInfo.BuildNumber)"
    Write-Host "Arquitectura: $($osInfo.OSArchitecture)"
    $uptime = (Get-Date) - $osInfo.LastBootUpTime
    Write-Host "Tiempo de Actividad (Uptime): $($uptime.Days) días, $($uptime.Hours) horas, $($uptime.Minutes) minutos"
    Write-Host "Último reinicio: $($osInfo.LastBootUpTime)"
}
catch {
    Write-Warning "No se pudo obtener la información general del sistema. Error: $($_.Exception.Message)"
}
Write-Host "`n"
#endregion

#region Rendimiento de CPU (General)
Write-Host "===== RENDIMIENTO DE CPU (GENERAL) =====" -ForegroundColor Cyan
try {
    $cpu = Get-CimInstance Win32_Processor
    Write-Host "Procesador: $($cpu.Name)"
    Write-Host "Número de núcleos lógicos: $($cpu.NumberOfLogicalProcessors)"
    Write-Host "Carga actual de CPU (todos los núcleos): $($cpu.LoadPercentage) %"
    $Global:NumberOfCores = $cpu.NumberOfLogicalProcessors # Guardar para usar después
}
catch {
    Write-Warning "No se pudo obtener la información de la CPU. Error: $($_.Exception.Message)"
    $Global:NumberOfCores = $env:NUMBER_OF_PROCESSORS # Fallback
}
Write-Host "`n"
#endregion

#region Uso de Memoria RAM
Write-Host "===== USO DE MEMORIA RAM =====" -ForegroundColor Cyan
try {
    $mem = Get-CimInstance Win32_OperatingSystem
    $totalRAM_GB = [math]::Round($mem.TotalVisibleMemorySize / 1MB, 2) # TotalVisibleMemorySize está en KB, 1MB es 1024*1024 bytes, así que KB / (1024) = MB
    $freeRAM_GB = [math]::Round($mem.FreePhysicalMemory / 1MB, 2)     # FreePhysicalMemory está en KB
    $usedRAM_GB = $totalRAM_GB - $freeRAM_GB
    $percentUsedRAM = if ($totalRAM_GB -gt 0) { [math]::Round(($usedRAM_GB / $totalRAM_GB) * 100, 2) } else { 0 }

    Write-Host "RAM Total: $totalRAM_GB GB"
    Write-Host "RAM Libre: $freeRAM_GB GB"
    Write-Host "RAM Usada: $($usedRAM_GB) GB ($percentUsedRAM %)"
}
catch {
    Write-Warning "No se pudo obtener la información de la RAM. Error: $($_.Exception.Message)"
}
Write-Host "`n"
#endregion

#region Espacio en Disco
Write-Host "===== ESPACIO EN DISCO =====" -ForegroundColor Cyan
try {
    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        if ($_.Used -ne $null -and $_.Free -ne $null) { # Asegurarse que las propiedades existen (evita errores con algunas unidades)
            $driveName = $_.Name
            $usedSpaceGB = [math]::Round($_.Used / 1GB, 2)
            $freeSpaceGB = [math]::Round($_.Free / 1GB, 2)
            $totalSpaceGB = $usedSpaceGB + $freeSpaceGB
            if ($totalSpaceGB -gt 0) {
                $percentFree = [math]::Round(($freeSpaceGB / $totalSpaceGB) * 100, 2)
                Write-Host "Unidad $driveName :"
                Write-Host "  Espacio Total: $totalSpaceGB GB"
                Write-Host "  Espacio Usado: $usedSpaceGB GB"
                Write-Host "  Espacio Libre: $freeSpaceGB GB ($percentFree % libre)"
            }
        }
    }

    Write-Host "`n--- Unidad con MENOR espacio libre ---"
    Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Free -ne $null} | Sort-Object Free -Ascending | Select-Object -First 1 | ForEach-Object {
        $used = [math]::Round((($_.Used) / 1GB), 2)
        $free = [math]::Round((($_.Free) / 1GB), 2)
        $total = $used + $free
        Write-Host "Unidad más llena: $($_.Name)"
        Write-Host "  Espacio usado: $used GB / $total GB"
        Write-Host "  Libre: $free GB"
    }
}
catch {
    Write-Warning "No se pudo obtener la información de espacio en disco. Error: $($_.Exception.Message)"
}
Write-Host "`n"
#endregion

#region Rendimiento de Discos Físicos (I/O)
Write-Host "===== RENDIMIENTO DE DISCOS FÍSICOS (I/O) =====" -ForegroundColor Cyan
try {
    if (-not $Global:isAdmin) {
        Write-Warning "Se requieren privilegios de Administrador para obtener contadores de rendimiento de disco detallados."
    }

    Write-Host "`n--- Resumen General (_Total) ---"
    Get-Counter '\PhysicalDisk(_Total)\% Disk Time' -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("  Porcentaje de tiempo de disco activo (Total): {0:N2} %" -f $_.CounterSamples.CookedValue) }
    Get-Counter '\PhysicalDisk(_Total)\Avg. Disk Queue Length' -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("  Longitud promedio de la cola del disco (Total): {0:N2}" -f $_.CounterSamples.CookedValue) }
    Get-Counter '\PhysicalDisk(_Total)\Disk Bytes/sec' -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("  Velocidad de transferencia del disco (Total): {0:N2} MB/s" -f ($_.CounterSamples.CookedValue / 1MB)) }

    Write-Host "`n--- Detalles por Instancia de Disco Físico ---"
    $diskCounters = Get-Counter -Counter "\PhysicalDisk(*)\% Disk Time", "\PhysicalDisk(*)\Avg. Disk Queue Length", "\PhysicalDisk(*)\Disk Bytes/sec" -ErrorAction SilentlyContinue
    
    if ($diskCounters) {
        $GroupedCounters = $diskCounters | Group-Object InstanceName
        
        foreach ($group in $GroupedCounters) {
            $instanceName = $group.Name
            if ($instanceName -eq "_Total") { continue } # Ya cubierto

            Write-Host "  Disco Físico (Instancia del contador: $instanceName):"
            
            $diskTime = $group.Group | Where-Object {$_.Path -like "*\% disk time"}
            if ($diskTime) { Write-Host ("    Porcentaje de tiempo de disco activo: {0:N2} %" -f $diskTime.CounterSamples.CookedValue) }
            
            $queueLength = $group.Group | Where-Object {$_.Path -like "*\avg. disk queue length"}
            if ($queueLength) { Write-Host ("    Longitud promedio de la cola del disco: {0:N2}" -f $queueLength.CounterSamples.CookedValue) }
            
            $bytesPerSec = $group.Group | Where-Object {$_.Path -like "*\disk bytes/sec"}
            if ($bytesPerSec) { Write-Host ("    Velocidad de transferencia del disco: {0:N2} MB/s" -f ($bytesPerSec.CounterSamples.CookedValue / 1MB)) }
        }
    } else {
        Write-Host "  No se pudieron obtener contadores individuales para los discos físicos o no hay actividad."
    }
} catch {
    Write-Warning "No se pudieron obtener los contadores de rendimiento del disco. Error: $($_.Exception.Message)"
}
Write-Host "`n"
#endregion

#region Uso del Archivo de Paginación
Write-Host "===== USO DEL ARCHIVO DE PAGINACIÓN =====" -ForegroundColor Cyan
try {
    Get-Counter '\Paging File(_Total)\% Usage' -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("  Porcentaje de uso actual del archivo de paginación: {0:N2} %" -f $_.CounterSamples.CookedValue) }
    Get-Counter '\Paging File(_Total)\% Usage Peak' -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("  Pico de uso del archivo de paginación: {0:N2} %" -f $_.CounterSamples.CookedValue) }
} catch {
    Write-Warning "No se pudieron obtener los contadores del archivo de paginación. Error: $($_.Exception.Message)"
}
Write-Host "`n"
#endregion

#region Top 5 Procesos por Uso de CPU (Instantáneo Aproximado)
Write-Host "===== TOP 5 PROCESOS POR USO DE CPU (INSTANTÁNEO APROXIMADO) =====" -ForegroundColor Cyan
$IntervalSeconds = 2 # Intervalo más corto para una respuesta más rápida, puede ajustarse a 2-3 para más precisión
Write-Host "(Midiendo durante $IntervalSeconds segundos...)"

try {
    # Primera muestra
    $ProcessList1 = Get-Process | Where-Object {$_.ProcessName -ne "Idle" -and $_.Id -ne 0} # Excluir Idle y System (Id 0)
    $Time1 = Get-Date

    Start-Sleep -Seconds $IntervalSeconds

    # Segunda muestra
    $ProcessList2 = Get-Process | Where-Object {$_.ProcessName -ne "Idle" -and $_.Id -ne 0}
    $Time2 = Get-Date

    $ElapsedTime = ($Time2 - $Time1).TotalSeconds
    if ($ElapsedTime -eq 0) { $ElapsedTime = $IntervalSeconds } # Evitar división por cero si el sleep fue muy corto

    $ProcessInfo = @{}
    foreach ($p1 in $ProcessList1) {
        $p2 = $ProcessList2 | Where-Object {$_.Id -eq $p1.Id}
        if ($p2) {
            $cpuTimeDiff = $p2.TotalProcessorTime.TotalSeconds - $p1.TotalProcessorTime.TotalSeconds
            
            # Si un proceso acaba de empezar, p1.TotalProcessorTime puede ser $null o 0.
            # Si un proceso terminó, p2 podría no existir (ya filtrado).
            # Handle counter wrap or new process instance with same PID (raro, pero posible)
            if ($cpuTimeDiff -lt 0) {$cpuTimeDiff = $p2.TotalProcessorTime.TotalSeconds} 

            # % de CPU = (Tiempo de CPU usado por el proceso / Tiempo transcurrido total) / Número de Cores Lógicos * 100
            # Esto da el porcentaje del total de la capacidad de CPU del sistema.
            $cpuPercent = ($cpuTimeDiff / $ElapsedTime) / $Global:NumberOfCores * 100
            
            $ProcessInfo[$p1.Id] = @{
                Name          = $p1.ProcessName
                Id            = $p1.Id
                CPU_Percent   = [math]::Round($cpuPercent, 2)
                WorkingSet_MB = [math]::Round($p2.WorkingSet / 1MB, 2)
                Handles       = $p2.Handles
                Path          = try { $p2.Path } catch { "N/A" } # Path puede requerir admin para algunos procesos
            }
        }
    }

    # Ordenar y seleccionar top 5
    $ProcessInfo.Values | Where-Object {$_.CPU_Percent -gt 0.01} | Sort-Object CPU_Percent -Descending | Select-Object -First 5 |
        Format-Table Name, Id, CPU_Percent, WorkingSet_MB, Handles, Path -AutoSize -Wrap
}
catch {
    Write-Warning "No se pudo calcular el uso de CPU por proceso. Error: $($_.Exception.Message)"
    Write-Host "Como alternativa, mostrando procesos por tiempo de CPU acumulado (Get-Process | Sort CPU):"
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | Format-Table -AutoSize Name, CPU, ID, WorkingSet
}
Write-Host "`n"
#endregion

#region Top 5 Procesos por Uso de RAM
Write-Host "===== TOP 5 PROCESOS POR USO DE RAM (WorkingSet) =====" -ForegroundColor Cyan
try {
    Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5 | 
        Select-Object Name, ID, @{Name="WorkingSet_MB";Expression={[math]::Round($_.WorkingSet / 1MB,2)}}, Handles, Path |
        Format-Table -AutoSize -Wrap
}
catch {
    Write-Warning "No se pudo obtener la lista de procesos por uso de RAM. Error: $($_.Exception.Message)"
}
Write-Host "`n"
#endregion

#region Registros de Eventos Recientes
Write-Host "===== REGISTROS DE EVENTOS RECIENTES (ERRORES/CRÍTICOS) =====" -ForegroundColor Cyan
$MaxEventsToCheck = 50 # Buscar en los últimos 50 eventos
$EventsToShow = 5    # Mostrar los 5 más recientes de esos

# Errores del Sistema
Write-Host "`n--- Últimos $EventsToShow Errores Críticos/Error del Registro del SISTEMA ---"
try {
    $SystemEvents = Get-WinEvent -LogName System -MaxEvents $MaxEventsToCheck -ErrorAction SilentlyContinue | 
                    Where-Object {$_.LevelDisplayName -in ("Critical", "Error")} | 
                    Select-Object -First $EventsToShow
    if ($SystemEvents) {
        $SystemEvents | Format-Table TimeCreated, ProviderName, ID, Message -AutoSize -Wrap
    } else {
        Write-Host "  No se encontraron errores críticos o de sistema recientes en los últimos $MaxEventsToCheck eventos."
    }
} catch {
    Write-Warning "No se pudo acceder al registro de eventos del sistema. Error: $($_.Exception.Message)"
}

# Errores de Aplicación
Write-Host "`n--- Últimos $EventsToShow Errores Críticos/Error del Registro de APLICACIÓN ---"
try {
    $AppEvents = Get-WinEvent -LogName Application -MaxEvents $MaxEventsToCheck -ErrorAction SilentlyContinue | 
                 Where-Object {$_.LevelDisplayName -in ("Critical", "Error")} | 
                 Select-Object -First $EventsToShow
    if ($AppEvents) {
        $AppEvents | Format-Table TimeCreated, ProviderName, ID, Message -AutoSize -Wrap
    } else {
        Write-Host "  No se encontraron errores críticos o de aplicación recientes en los últimos $MaxEventsToCheck eventos."
    }
} catch {
    Write-Warning "No se pudo acceder al registro de eventos de aplicación. Error: $($_.Exception.Message)"
}
Write-Host "`n"
#endregion

#region Programas de Inicio
Write-Host "===== PROGRAMAS DE INICIO =====" -ForegroundColor Cyan

# Desde Win32_StartupCommand (Registro)
Write-Host "`n--- Desde Registro (Win32_StartupCommand) ---"
try {
    $StartupCommands = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
    if ($StartupCommands) {
        $StartupCommands | Select-Object Name, Command, Location, User | Format-Table -AutoSize -Wrap
    } else {
        Write-Host "  No se encontraron programas de inicio vía Win32_StartupCommand."
    }
} catch {
    Write-Warning "No se pudieron obtener los programas de inicio de Win32_StartupCommand. Error: $($_.Exception.Message)"
}

# Desde Carpetas de Inicio
Function Get-StartupItemsFromFolder($FolderPath, $Scope) {
    Write-Host "`n--- Desde Carpeta de Inicio ($Scope) ---"
    Write-Host "Ruta: $FolderPath"
    if (Test-Path $FolderPath) {
        $items = Get-ChildItem $FolderPath -ErrorAction SilentlyContinue
        if ($items) {
            $items | Select-Object Name, FullName, LastWriteTime | Format-Table -AutoSize -Wrap
        } else {
            Write-Host "  Carpeta de inicio vacía."
        }
    } else {
        Write-Host "  Carpeta de inicio no encontrada."
    }
}

# Carpeta de Inicio del Usuario Actual
$userStartupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
Get-StartupItemsFromFolder -FolderPath $userStartupPath -Scope "Usuario Actual"

# Carpeta de Inicio Común (Todos los Usuarios)
$commonStartupPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
Get-StartupItemsFromFolder -FolderPath $commonStartupPath -Scope "Común (Todos los Usuarios)"

Write-Host "`n"
#endregion

#region Salud de Discos Físicos (S.M.A.R.T.)
Write-Host "===== ESTADO DE SALUD DE LOS DISCOS FÍSICOS (S.M.A.R.T.) =====" -ForegroundColor Cyan
if (-not $Global:isAdmin) {
    Write-Warning "Se requieren privilegios de Administrador para obtener datos S.M.A.R.T. detallados."
}
try {
    $physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($physicalDisks) {
        Write-Host "`n--- Resumen de Discos Físicos ---"
        $physicalDisks | Select-Object DeviceID, FriendlyName, MediaType, HealthStatus, OperationalStatus, FirmwareVersion, @{Name="Size_GB"; Expression={[math]::Round($_.Size / 1GB, 2)}} |
            Format-Table -AutoSize -Wrap
        
        Write-Host "`n--- Detalles de Fiabilidad (Contadores S.M.A.R.T. seleccionados) ---"
        foreach ($disk in $physicalDisks) {
            Write-Host "`n  Disco: $($disk.FriendlyName) (DeviceID: $($disk.DeviceID), MediaType: $($disk.MediaType))"
            $reliabilityCounters = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction SilentlyContinue
            if ($reliabilityCounters) {
                $reliabilityCounters | Select-Object Temperature, Wear, ReadErrorsTotal, WriteErrorsTotal, UncorrectableReadErrors, UncorrectableWriteErrors, PowerOnHours | Format-List
            } else {
                Write-Host "    No se pudieron obtener contadores de fiabilidad para este disco (podría requerir Admin o no ser soportado)."
            }
        }
    } else {
        Write-Host "  No se encontraron discos físicos o no se pudieron consultar."
    }
} catch {
    Write-Warning "No se pudieron obtener los datos de S.M.A.R.T. de los discos. Error: $($_.Exception.Message)"
}
Write-Host "`n"
#endregion

Write-Host "===== FIN DEL INFORME DE RENDIMIENTO AVANZADO =====" -ForegroundColor Yellow

