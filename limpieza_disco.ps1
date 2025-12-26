<#
.SYNOPSIS
    Script para liberar espacio en disco en sistemas Windows.
.DESCRIPTION
    Este script proporciona un menú interactivo para realizar varias tareas de limpieza
    y liberar espacio en la unidad del sistema.
.NOTES
    Autor: Gemini
    Fecha: 20/10/2025
    Requiere ejecución como Administrador.
#>

#region Configuracion Inicial
$OutputEncoding = [System.Text.Encoding]::UTF8
$Global:TotalEspacioLiberado = 0

# Capturar espacio libre inicial en C: para comparativa final
try {
    $driveC = Get-PSDrive -Name C -ErrorAction SilentlyContinue
    if ($driveC) {
        $Global:EspacioLibreInicial = $driveC.Free
    } else {
        $Global:EspacioLibreInicial = 0
    }
} catch {
    $Global:EspacioLibreInicial = 0
}
#endregion

#region Comprobar privilegios de Administrador
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Este script requiere privilegios de Administrador. Por favor, ejecútalo desde una consola de PowerShell como Administrador."
    Start-Sleep -Seconds 5
    Exit
}
#endregion

function Get-FolderSize {
    param([string]$Path)
    if (Test-Path $Path) {
        return (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    }
    return 0
}

function Limpiar-ArchivosTemporales {
    Write-Host "--- Limpiando Archivos Temporales ---" -ForegroundColor Cyan
    $tempPaths = @(
        "$env:TEMP",
        "$env:SystemRoot\Temp"
    ) | Get-Unique
    $totalLiberado = 0

    foreach ($path in $tempPaths) {
        if (Test-Path $path) {
            Write-Host "Limpiando la carpeta: $path"
            $tamanioAntes = Get-FolderSize -Path $path
            
            Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            $tamanioDespues = Get-FolderSize -Path $path

            $liberado = $tamanioAntes - $tamanioDespues
            if ($liberado -lt 0) { $liberado = 0 } # Evitar negativos por cambios en tiempo real
            $totalLiberado += $liberado
            Write-Host "Espacio liberado en '$path': $([math]::Round($liberado / 1MB, 2)) MB" -ForegroundColor Green
        } else {
            Write-Warning "La ruta $path no existe o no es accesible."
        }
    }
    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Total liberado en esta operación: $([math]::Round($totalLiberado / 1MB, 2)) MB" -ForegroundColor Green
    $Global:TotalEspacioLiberado += $totalLiberado
    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
}

function Limpiar-CacheUpdate {
    Write-Host "--- Limpiando Caché de Windows Update ---" -ForegroundColor Cyan
    $updateCachePath = "$env:SystemRoot\SoftwareDistribution\Download"
    $totalLiberado = 0

    if (Test-Path $updateCachePath) {
        Write-Host "Deteniendo el servicio de Windows Update (wuauserv)..."
        $status = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if ($status.Status -ne 'Stopped') {
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Limpiando la carpeta: $updateCachePath"
        $tamanioAntes = Get-FolderSize -Path $updateCachePath

        Get-ChildItem -Path $updateCachePath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        $tamanioDespues = Get-FolderSize -Path $updateCachePath
        
        $liberado = $tamanioAntes - $tamanioDespues
        if ($liberado -lt 0) { $liberado = 0 }
        $totalLiberado = $liberado

        Write-Host "Iniciando el servicio de Windows Update (wuauserv)..."
        if ($status.Status -ne 'Stopped') {
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        }

        Write-Host "-------------------------------------------------" -ForegroundColor Cyan
        Write-Host "Total liberado en esta operación: $([math]::Round($totalLiberado / 1MB, 2)) MB" -ForegroundColor Green
        $Global:TotalEspacioLiberado += $totalLiberado
        Write-Host "-------------------------------------------------" -ForegroundColor Cyan
    } else {
        Write-Warning "La ruta $updateCachePath no existe o no es accesible."
    }
}

function Vaciar-Papelera {
    param(
        [switch]$ForceClean
    )
    Write-Host "--- Vaciando Papelera de Reciclaje ---" -ForegroundColor Cyan
    
    # Intentar medir la papelera antes de vaciar (Usando carpeta oculta $Recycle.Bin en C:)
    $recyclePath = "C:\`$Recycle.Bin"
    $tamanioAntes = 0
    if (Test-Path $recyclePath) {
        $tamanioAntes = Get-FolderSize -Path $recyclePath
    }

    if ($ForceClean) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    } else {
        # Si no es force, pedirá confirmación. Si el usuario cancela, el cálculo "Después" lo reflejará.
        Clear-RecycleBin -ErrorAction SilentlyContinue
    }
    
    $tamanioDespues = 0
    if (Test-Path $recyclePath) {
        $tamanioDespues = Get-FolderSize -Path $recyclePath
    }
    
    $liberado = $tamanioAntes - $tamanioDespues
    if ($liberado -gt 0) {
        Write-Host "Espacio liberado de la Papelera: $([math]::Round($liberado / 1MB, 2)) MB" -ForegroundColor Green
        $Global:TotalEspacioLiberado += $liberado
    }

    Write-Host "Operación de Papelera finalizada." -ForegroundColor Green
    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
}

function Limpiar-WinSxS {
    Write-Host "--- Limpiando Almacén de Componentes (WinSxS) ---" -ForegroundColor Cyan
    Write-Host "Este proceso puede tardar varios minutos. Por favor, sé paciente." -ForegroundColor Yellow

    Write-Host "Ejecutando: dism.exe /online /cleanup-image /startcomponentcleanup"
    Start-Process "dism.exe" -ArgumentList "/online /cleanup-image /startcomponentcleanup" -Wait -NoNewWindow

    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Limpieza del almacén de componentes completada." -ForegroundColor Green
    Write-Host "Nota: El espacio ganado aquí se reflejará en el reporte final de 'Espacio en C:'." -ForegroundColor Gray
    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
}

function Limpiar-Logs {
    Write-Host "--- Limpiando Registros de Diagnóstico y Eventos ---" -ForegroundColor Cyan

    # Medir logs de eventos antes
    $evtLogsPath = "$env:SystemRoot\System32\winevt\Logs"
    $tamanioEvtAntes = Get-FolderSize -Path $evtLogsPath

    Write-Host "Limpiando registros de eventos de Windows..."
    Get-WinEvent -ListLog * | ForEach-Object {
        wevtutil.exe cl $_.LogName 2>$null
    }
    
    # Medir logs de eventos después
    $tamanioEvtDespues = Get-FolderSize -Path $evtLogsPath
    $liberadoEvt = $tamanioEvtAntes - $tamanioEvtDespues
    if ($liberadoEvt -gt 0) {
        Write-Host "Espacio liberado en Logs de Eventos: $([math]::Round($liberadoEvt / 1MB, 2)) MB" -ForegroundColor Green
        $Global:TotalEspacioLiberado += $liberadoEvt
    }

    # Limpieza de logs de archivo (CBS/DISM)
    $logPaths = @(
        "$env:SystemRoot\Logs\CBS",
        "$env:SystemRoot\Logs\DISM"
    )
    
    $totalLiberadoArchivos = 0

    foreach ($path in $logPaths) {
        if (Test-Path $path) {
            Write-Host "Limpiando la carpeta: $path"
            $tamanioAntes = Get-FolderSize -Path $path
            
            Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            $tamanioDespues = Get-FolderSize -Path $path

            $liberado = $tamanioAntes - $tamanioDespues
            if ($liberado -lt 0) { $liberado = 0 }
            $totalLiberadoArchivos += $liberado
            Write-Host "Espacio liberado en '$path': $([math]::Round($liberado / 1MB, 2)) MB" -ForegroundColor Green
        }
    }

    $Global:TotalEspacioLiberado += $totalLiberadoArchivos

    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Total liberado en esta operación (Eventos + Archivos): $([math]::Round(($liberadoEvt + $totalLiberadoArchivos) / 1MB, 2)) MB" -ForegroundColor Green
    Write-Host "Limpieza de registros completada." -ForegroundColor Green
    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
}


function Mostrar-Menu {
    Clear-Host
    Write-Host "=============================================="
    Write-Host "   SCRIPT DE LIMPIEZA DE DISCO - WINDOWS"
    Write-Host "=============================================="
    Write-Host "Selecciona una opción:"
    Write-Host "1. Limpiar archivos temporales (Usuario y Sistema)"
    Write-Host "2. Limpiar caché de Windows Update"
    Write-Host "3. Vaciar Papelera de Reciclaje"
    Write-Host "4. Limpiar almacén de componentes (WinSxS)"
    Write-Host "5. Limpiar registros de diagnóstico y eventos"
    Write-Host "6. REALIZAR TODAS LAS LIMPIEZAS"
    Write-Host "Q. Salir y ver INFORME FINAL"
    Write-Host "=============================================="
}

do {
    Mostrar-Menu
    $opcion = Read-Host "Introduce tu opción"

    switch ($opcion) {
        "1" {
            Limpiar-ArchivosTemporales
            Write-Host "Pulsa Enter para continuar..."
            Read-Host | Out-Null
        }
        "2" {
            Limpiar-CacheUpdate
            Write-Host "Pulsa Enter para continuar..."
            Read-Host | Out-Null
        }
        "3" {
            Vaciar-Papelera
            Write-Host "Pulsa Enter para continuar..."
            Read-Host | Out-Null
        }
        "4" {
            Limpiar-WinSxS
            Write-Host "Pulsa Enter para continuar..."
            Read-Host | Out-Null
        }
        "5" {
            Limpiar-Logs
            Write-Host "Pulsa Enter para continuar..."
            Read-Host | Out-Null
        }
        "6" {
            Write-Host "--- REALIZANDO TODAS LAS LIMPIEZAS ---" -ForegroundColor Green
            Limpiar-ArchivosTemporales
            Limpiar-CacheUpdate
            Vaciar-Papelera -ForceClean
            Limpiar-WinSxS
            Limpiar-Logs
            Write-Host "--- TODAS LAS TAREAS DE LIMPIEZA HAN FINALIZADO ---" -ForegroundColor Green
            Write-Host "Pulsa Enter para ver el reporte final..."
            Read-Host | Out-Null
        }
        "q" {
            Clear-Host
            Write-Host "================ RESUMEN FINAL ================" -ForegroundColor Cyan
            $totalMB = [math]::Round($Global:TotalEspacioLiberado / 1MB, 2)
            $totalGB = [math]::Round($Global:TotalEspacioLiberado / 1GB, 4)
            
            Write-Host "1. Espacio liberado (Archivos eliminados por el script):" -ForegroundColor White
            Write-Host "   $totalMB MB ($totalGB GB)" -ForegroundColor Green
            
            Write-Host "`n2. Impacto real en Disco C: (Sistema):" -ForegroundColor White
            if ($Global:EspacioLibreInicial -gt 0) {
                $driveC = Get-PSDrive -Name C -ErrorAction SilentlyContinue
                if ($driveC) {
                    $espacioFinal = $driveC.Free
                    $diferenciaReal = $espacioFinal - $Global:EspacioLibreInicial
                    $diferenciaRealGB = [math]::Round($diferenciaReal / 1GB, 4)
                    
                    if ($diferenciaReal -gt 0) {
                        Write-Host "   Has recuperado: $diferenciaRealGB GB libres en C:" -ForegroundColor Magenta
                    } elseif ($diferenciaReal -lt 0) {
                        Write-Host "   El espacio libre disminuyó en: $diferenciaRealGB GB" -ForegroundColor Red
                        Write-Host "   (Posiblemente descargas en segundo plano o archivos de paginación crecieron)" -ForegroundColor Gray
                    } else {
                        Write-Host "   Sin cambios en el espacio libre total." -ForegroundColor Yellow
                    }
                }
            } else {
                Write-Host "   (No se pudo calcular el espacio inicial)" -ForegroundColor Gray
            }
            Write-Host "===============================================" -ForegroundColor Cyan
            Write-Host "Gracias por usar el script."
            Start-Sleep -Seconds 2
        }
        default {
            Write-Host "Opción no válida. Inténtalo de nuevo." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($opcion -ne 'q')
