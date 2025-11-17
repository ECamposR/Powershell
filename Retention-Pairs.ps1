<#PSScriptInfo
.VERSION 1.0.0
.GUID 6b4b6c4b-1c3d-4a2d-8a4a-6f7f1a5b2e77
.AUTHOR Equipo Ops
.COPYRIGHT (c) 2025. All rights reserved.
#>

<#
.SYNOPSIS
   Política de retención por pares de backups (.sql + .zip) basada en la clave de nombre YYYYMMDDhhmmss.

.DESCRIPTION
   - Detecta pares completos cuando existen ambos archivos (.sql y .zip) con la misma "clave" (timestamp de 14 dígitos en el nombre).
   - Mantiene SIEMPRE al menos N pares (por defecto 5), nunca borra por debajo de ese mínimo.
   - Borra pares completos más antiguos hasta dejar exactamente N pares completos.
   - Nunca toca archivos de pares incompletos; los reporta como "incompletos".
   - Ordena por clave (nombre), no por LastWriteTime.
   - Idempotente: múltiples ejecuciones no producen inconsistencias.
   - Eficiente con miles de archivos (una pasada + estructura hash).
   - Logging detallado y códigos de salida:
        0 = Éxito
        1 = Error de E/S (ruta inválida, disco, etc.)
        2 = Permisos insuficientes
        3 = Inconsistencias graves / error no controlado

.PARAMETER BackupPath
   Ruta del directorio con los backups (.sql/.zip). Solo se procesan archivos que cumplan el patrón ^\d{14}\.(sql|zip)$.

.PARAMETER MinPairsToKeep
   Cantidad mínima de pares completos a conservar. Por defecto 5.

.PARAMETER LogPath
   Ruta del archivo de log. Por defecto: <BackupPath>\Retention-YYYYMMDD.log. Si falla, usa %TEMP%.

.PARAMETER DryRun
   Si $true, simula (no elimina). Por defecto $false.

.EXAMPLE
   .\Retention-Pairs.ps1 -BackupPath "D:\Backups\DB" -MinPairsToKeep 5

.EXAMPLE
   .\Retention-Pairs.ps1 -BackupPath "D:\Backups\DB" -DryRun $true
   # Simula la política, registra lo que HABRÍA eliminado.

.NOTES
   Compatible con Windows Server Core 2022, PowerShell 5.1+. No requiere módulos de terceros.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BackupPath,

    [ValidateRange(1, 100000)]
    [int]$MinPairsToKeep = 5,

    [string]$LogPath = $null,

    [bool]$DryRun = $false
)

#region Config / Globals
$ErrorActionPreference = 'Stop'
$script:ExitCode = 0

# Regex de archivos válidos: "YYYYMMDDhhmmss.sql|zip"
#   key = 14 dígitos; ext = sql|zip
$KeyRegex = '^(?<key>\d{14})\.(?<ext>sql|zip)$'

# Estructuras de trabajo
# $Pairs: [key] -> @{ sql = <FullName or $null>; zip = <FullName or $null> }
$Pairs = @{}
$Incomplete = New-Object System.Collections.Generic.List[string]
$Ignored = New-Object System.Collections.Generic.List[string]
$ToDelete = New-Object System.Collections.Generic.List[hashtable]

# Logging
function Initialize-Log {
    param([string]$TargetDir, [string]$CustomPath)

    try {
        if ([string]::IsNullOrWhiteSpace($CustomPath)) {
            $date = Get-Date -Format 'yyyyMMdd'
            $proposed = Join-Path -Path $TargetDir -ChildPath ("Retention-{0}.log" -f $date)
        } else {
            $proposed = $CustomPath
        }

        $dir = Split-Path -Path $proposed -Parent
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        if (-not (Test-Path -LiteralPath $proposed)) {
            New-Item -ItemType File -Path $proposed -Force | Out-Null
        }
        return $proposed
    }
    catch {
        # Fallback a %TEMP%
        $fallback = Join-Path -Path $env:TEMP -ChildPath ("Retention-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
        try {
            if (-not (Test-Path -LiteralPath $fallback)) {
                New-Item -ItemType File -Path $fallback -Force | Out-Null
            }
            return $fallback
        }
        catch {
            Write-Warning "No se pudo crear el log ni en la ruta objetivo ni en %TEMP%. Continuando sin archivo de log."
            return $null
        }
    }
}

$LogFile = Initialize-Log -TargetDir $BackupPath -CustomPath $LogPath

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')] [string]$Level = 'INFO'
    )
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fffK')
    $line = "[{0}] [{1}] {2}" -f $stamp, $Level, $Message
    Write-Host $line
    if ($LogFile) { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 }
}

function Set-ExitCode {
    param([int]$Code)
    if ($Code -gt $script:ExitCode) { $script:ExitCode = $Code }
}
#endregion

try {
    #region Validaciones de entrada
    if (-not (Test-Path -LiteralPath $BackupPath)) {
        Write-Log -Level 'ERROR' -Message "La ruta '$BackupPath' no existe."
        Set-ExitCode 1
        exit $script:ExitCode
    }
    $BackupPath = (Resolve-Path -LiteralPath $BackupPath).Path
    Write-Log "Inicio de política de retención en: $BackupPath (MinPairsToKeep=$MinPairsToKeep, DryRun=$DryRun)"
    #endregion

    #region Enumeración eficiente
    # Nota: Get-ChildItem -File es suficientemente eficiente en PS 5.1; evitamos cargar todo en memoria con select innecesarios.
    $filesEnum = Get-ChildItem -LiteralPath $BackupPath -File -ErrorAction Stop
    foreach ($f in $filesEnum) {
        $m = [regex]::Match($f.Name, $KeyRegex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) {
            $key = $m.Groups['key'].Value
            $ext = $m.Groups['ext'].Value.ToLowerInvariant()

            if (-not $Pairs.ContainsKey($key)) {
                $Pairs[$key] = @{ sql = $null; zip = $null }
            }
            if ($Pairs[$key][$ext]) {
                # Duplicado inesperado (dos .sql o dos .zip con la misma clave). No borramos nada, lo reportamos.
                Write-Log -Level 'WARN' -Message "Clave '$key' tiene múltiples archivos '.$ext'. Se ignoran duplicados para evitar inconsistencias."
                # Preferimos conservar el primero, pero registramos como inconsistencia leve.
                Set-ExitCode 3
                continue
            }
            $Pairs[$key][$ext] = $f.FullName
        }
        else {
            # Archivo no relacionado (o corrupto de nombre). Se ignora limpiamente.
            $Ignored.Add($f.FullName) | Out-Null
        }
    }
    #endregion

    #region Clasificación por estado (completos vs incompletos)
    $completeKeys = New-Object System.Collections.Generic.List[string]
    foreach ($key in $Pairs.Keys) {
        $pair = $Pairs[$key]
        if ($pair.sql -and $pair.zip) {
            $completeKeys.Add($key) | Out-Null
        } else {
            $Incomplete.Add($key) | Out-Null
        }
    }

    # Orden descendente por clave (YYYYMMDDhhmmss): lexical == cronológico
    $completeKeys = $completeKeys | Sort-Object -Descending

    $totalComplete = $completeKeys.Count
    $totalIncomplete = $Incomplete.Count

    Write-Log ("Detectados pares completos: {0}; pares incompletos: {1}" -f $totalComplete, $totalIncomplete)

    # Si hay menos de MinPairsToKeep, no se elimina nada.
    if ($totalComplete -lt $MinPairsToKeep) {
        Write-Log -Level 'WARN' -Message ("Hay {0} pares completos (< {1}). Política: NO BORRAR NADA." -f $totalComplete, $MinPairsToKeep)
        $deletedPairs = 0
        $retainedPairs = $totalComplete
    }
    else {
        # Determinar cuáles borrar (los más antiguos, es decir, de la cola después de los N primeros)
        if ($totalComplete -gt $MinPairsToKeep) {
            $toDeleteKeys = $completeKeys[$MinPairsToKeep..($totalComplete-1)]
        } else {
            $toDeleteKeys = @()
        }

        foreach ($k in $toDeleteKeys) {
            $pair = $Pairs[$k]
            $ToDelete.Add(@{ key = $k; sql = $pair.sql; zip = $pair.zip }) | Out-Null
        }

        $deletedPairs = 0
        foreach ($del in $ToDelete) {
            Write-Log -Level 'INFO' -Message ("Marcar para eliminación clave {0}: `n`t{1}`n`t{2}" -f $del.key, $del.sql, $del.zip)
            if (-not $DryRun) {
                foreach ($p in @($del.sql, $del.zip)) {
                    try {
                        # Intento de borrado tolerante a errores puntuales.
                        Remove-Item -LiteralPath $p -Force -ErrorAction Stop
                        Write-Log -Level 'DEBUG' -Message ("Eliminado: {0}" -f $p)
                    }
                    catch [System.UnauthorizedAccessException] {
                        Write-Log -Level 'ERROR' -Message ("Permisos insuficientes al eliminar: {0}. {1}" -f $p, $_.Exception.Message)
                        Set-ExitCode 2
                    }
                    catch [System.IO.IOException] {
                        Write-Log -Level 'ERROR' -Message ("Error de E/S (¿archivo bloqueado?) al eliminar: {0}. {1}" -f $p, $_.Exception.Message)
                        Set-ExitCode 1
                    }
                    catch {
                        Write-Log -Level 'ERROR' -Message ("Error inesperado al eliminar: {0}. {1}" -f $p, $_.Exception.Message)
                        Set-ExitCode 3
                    }
                }
            } else {
                Write-Log -Level 'INFO' -Message "(DryRun) No se elimina físicamente la clave {0}" -f $del.key
            }
            $deletedPairs++
        }

        $retainedPairs = [Math]::Max($totalComplete - $deletedPairs, 0)
    }
    #endregion

    #region Reporte de incompletos
    if ($totalIncomplete -gt 0) {
        Write-Log -Level 'WARN' -Message "Se detectaron claves INCOMPLETAS (no se tocan, revisar origen del backup parcial):"
        foreach ($k in $Incomplete | Sort-Object -Descending) {
            $pair = $Pairs[$k]
            $missing = @()
            if (-not $pair.sql) { $missing += '.sql' }
            if (-not $pair.zip) { $missing += '.zip' }
            Write-Log -Level 'WARN' -Message (" - {0} (faltan: {1})" -f $k, ($missing -join ', '))
        }
    }
    #endregion

    #region Resumen
    Write-Log -Level 'INFO' -Message "Resumen ejecución:"
    Write-Log -Level 'INFO' -Message (" - Pares completos totales: {0}" -f $totalComplete)
    Write-Log -Level 'INFO' -Message (" - Pares incompletos: {0}" -f $totalIncomplete)
    Write-Log -Level 'INFO' -Message (" - Pares eliminados: {0}" -f $deletedPairs)
    Write-Log -Level 'INFO' -Message (" - Pares retenidos: {0}" -f $retainedPairs)

    if ($DryRun) {
        Write-Log -Level 'INFO' -Message "Modo simulación (DryRun=TRUE): no se eliminó ningún archivo."
    }
    #endregion
}
catch [System.UnauthorizedAccessException] {
    Write-Log -Level 'ERROR' -Message ("Permisos insuficientes: {0}" -f $_.Exception.Message)
    Set-ExitCode 2
}
catch [System.IO.IOException] {
    Write-Log -Level 'ERROR' -Message ("Error de E/S: {0}" -f $_.Exception.Message)
    Set-ExitCode 1
}
catch {
    Write-Log -Level 'ERROR' -Message ("Error inesperado: {0}" -f $_.Exception.Message)
    Set-ExitCode 3
}
finally {
    Write-Log -Level 'INFO' -Message ("Fin. ExitCode={0}" -f $script:ExitCode)
    exit $script:ExitCode
}
