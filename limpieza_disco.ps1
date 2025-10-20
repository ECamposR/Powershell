ï»¿<#
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
#endregion

#region Comprobar privilegios de Administrador
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Este script requiere privilegios de Administrador. Por favor, ejecútalo desde una consola de PowerShell como Administrador."
    Start-Sleep -Seconds 5
    Exit
}
#endregion

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
            $items = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            $tamanioAntes = ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            
            $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            $itemsDespues = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            $tamanioDespues = ($itemsDespues | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum

            $liberado = $tamanioAntes - $tamanioDespues
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
        $items = Get-ChildItem -Path $updateCachePath -Recurse -Force -ErrorAction SilentlyContinue
        $tamanioAntes = ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum

        $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        $itemsDespues = Get-ChildItem -Path $updateCachePath -Recurse -Force -ErrorAction SilentlyContinue
        $tamanioDespues = ($itemsDespues | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        
        $liberado = $tamanioAntes - $tamanioDespues
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
    if ($ForceClean) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    } else {
        Clear-RecycleBin -ErrorAction SilentlyContinue
    }
    Write-Host "La Papelera de Reciclaje ha sido vaciada." -ForegroundColor Green
    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
}

function Limpiar-WinSxS {
    Write-Host "--- Limpiando Almacén de Componentes (WinSxS) ---" -ForegroundColor Cyan
    Write-Host "Este proceso puede tardar varios minutos. Por favor, sé paciente." -ForegroundColor Yellow

    Write-Host "Ejecutando: dism.exe /online /cleanup-image /startcomponentcleanup"
    Start-Process "dism.exe" -ArgumentList "/online /cleanup-image /startcomponentcleanup" -Wait -NoNewWindow

    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Limpieza del almacén de componentes completada." -ForegroundColor Green
    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
}

function Limpiar-Logs {
    Write-Host "--- Limpiando Registros de Diagnóstico y Eventos ---" -ForegroundColor Cyan

    Write-Host "Limpiando registros de eventos de Windows..."
    Get-WinEvent -ListLog * | ForEach-Object {
        wevtutil.exe cl $_.LogName 2>$null
    }

    $logPaths = @(
        "$env:SystemRoot\Logs\CBS",
        "$env:SystemRoot\Logs\DISM"
    )
    
    $totalLiberado = 0

    foreach ($path in $logPaths) {
        if (Test-Path $path) {
            Write-Host "Limpiando la carpeta: $path"
            $items = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            $tamanioAntes = ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            
            $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            $itemsDespues = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            $tamanioDespues = ($itemsDespues | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum

            $liberado = $tamanioAntes - $tamanioDespues
            $totalLiberado += $liberado
            Write-Host "Espacio liberado en '$path': $([math]::Round($liberado / 1MB, 2)) MB" -ForegroundColor Green
        } else {
            Write-Warning "La ruta $path no existe o no es accesible."
        }
    }

    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Total liberado en esta operación: $([math]::Round($totalLiberado / 1MB, 2)) MB" -ForegroundColor Green
    $Global:TotalEspacioLiberado += $totalLiberado
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
    Write-Host "Q. Salir"
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
            Write-Host "Espacio total recuperado en esta sesión: $([math]::Round($Global:TotalEspacioLiberado / 1GB, 2)) GB" -ForegroundColor Cyan
            Write-Host "Nota: El total no incluye el espacio recuperado por la limpieza de WinSxS ni la papelera de reciclaje." -ForegroundColor Yellow
            Write-Host "Pulsa Enter para continuar..."
            Read-Host | Out-Null
        }
        "q" {
            if ($Global:TotalEspacioLiberado -gt 0) {
                Write-Host "Espacio total recuperado en esta sesión: $([math]::Round($Global:TotalEspacioLiberado / 1GB, 2)) GB" -ForegroundColor Cyan
                Write-Host "Nota: El total no incluye el espacio recuperado por la limpieza de WinSxS ni la papelera de reciclaje." -ForegroundColor Yellow
            }
            Write-Host "Saliendo del script."
        }
        default {
            Write-Host "Opción no válida. Inténtalo de nuevo." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($opcion -ne 'q')