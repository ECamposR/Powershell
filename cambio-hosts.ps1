<# 
    Script: Parche temporal de hosts para Servidor5
    Uso: Ejecutar en cada endpoint con PowerShell como Administrador.
#>

# Verificar que se ejecuta como administrador
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Ejecuta este script en una consola de PowerShell con privilegios de administrador."
    exit 1
}

# Ruta del archivo hosts
$hostsPath = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"

if (-not (Test-Path $hostsPath)) {
    Write-Error "No se encontró el archivo hosts en $hostsPath"
    exit 1
}

# Backup del hosts (solo una vez)
$backupPath = "$hostsPath.bak"
if (-not (Test-Path $backupPath)) {
    Copy-Item -Path $hostsPath -Destination $backupPath -Force
    Write-Host "Backup del hosts creado en: $backupPath"
}

# Entradas que queremos asegurar en hosts
# Ajusta si cambian nombres o IP del servidor
$entries = @(
    "192.168.2.2`tServidor5`tServidor5.phsal.local"
)

# Función auxiliar para comprobar si ya existe alguna de las etiquetas de host en el archivo
function Test-HostEntryExists {
    param(
        [string]$HostsFile,
        [string]$HostToken
    )
    return Select-String -Path $HostsFile -Pattern "\b$([regex]::Escape($HostToken))\b" -Quiet
}

# Añadir entradas si no existen
$modified = $false

foreach ($entry in $entries) {
    # Tomamos el primer nombre después de la IP para comprobar
    $parts = $entry -split "`t| "
    if ($parts.Count -lt 2) { continue }

    # Comprobamos por el primer nombre (por ejemplo "Servidor5")
    $hostToken = $parts[1]

    if (-not (Test-HostEntryExists -HostsFile $hostsPath -HostToken $hostToken)) {
        Add-Content -Path $hostsPath -Value $entry
        Write-Host "Añadida entrada al hosts: $entry"
        $modified = $true
    }
    else {
        Write-Host "Ya existe una entrada para: $hostToken. No se duplica."
    }
}

if (-not $modified) {
    Write-Host "No fue necesario modificar el archivo hosts. Todo estaba ya aplicado."
} else {
    Write-Host "Parche aplicado correctamente al archivo hosts."
}

