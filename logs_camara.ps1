<#
.SYNOPSIS
    Recolecta logs de sistema, eventos y detalles del dispositivo de cámara en un único archivo de texto.

.DESCRIPTION
    Este script crea en C:\ un archivo llamado logs_yyyyMMdd_HHmmss.txt
    y vuelca en él:
      - Eventos de Application y System (hasta 10000 entradas).
      - Eventos de Drivers y PnP (si el canal existe y es accesible).
      - Información WMI de los dispositivos de cámara.
      - Salida de DxDiag.
      - Listado de controladores de cámara instalados (si existen).

.NOTES
    Ejecutar como administrador.
#>

# -------------------------------------------------------
# 1. Preparar archivo de salida
# -------------------------------------------------------
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = "C:\logs_$timestamp.txt"

"=== Inicio de extracción de logs: $(Get-Date) ===`n" |
    Out-File -FilePath $outputFile -Encoding UTF8

# -------------------------------------------------------
# 2. Función para extraer un log solo si es accesible
# -------------------------------------------------------
function Export-LogIfAccessible {
    param(
        [string]$LogName,
        [int]$MaxEvents = 1000
    )

    "## Eventos de $LogName (hasta $MaxEvents) ##" |
        Out-File -FilePath $outputFile -Append -Encoding UTF8

    try {
        # Comprueba existencia y acceso al canal
        Get-WinEvent -ListLog $LogName -ErrorAction Stop | Out-Null

        try {
            # Extrae eventos
            Get-WinEvent -LogName $LogName -MaxEvents $MaxEvents -ErrorAction Stop |
                Format-List TimeCreated, ProviderName, Id, LevelDisplayName, Message |
                Out-File -FilePath $outputFile -Append -Encoding UTF8
        }
        catch {
            "`tError al leer eventos de ${LogName}: $($_.Exception.Message)" |
                Out-File -FilePath $outputFile -Append -Encoding UTF8
        }
    }
    catch {
        "`tNo hay registros accesibles para ${LogName} o canal no existe" |
            Out-File -FilePath $outputFile -Append -Encoding UTF8
    }

    "`n" | Out-File -FilePath $outputFile -Append -Encoding UTF8
}

# -------------------------------------------------------
# 3. Exportar Application y System
# -------------------------------------------------------
Export-LogIfAccessible -LogName "Application" -MaxEvents 10000
Export-LogIfAccessible -LogName "System"      -MaxEvents 10000

# -------------------------------------------------------
# 4. Exportar Drivers y PnP si accesibles
# -------------------------------------------------------
$sources = @(
    "Microsoft-Windows-DriverFrameworks-UserMode/Operational",
    "Microsoft-Windows-Kernel-PnP/Diagnostic",
    "DeviceSetupManager"
)
foreach ($channel in $sources) {
    Export-LogIfAccessible -LogName $channel -MaxEvents 5000
}

# -------------------------------------------------------
# 5. Información WMI de la cámara
# -------------------------------------------------------
"## Información WMI de la cámara ##`n" |
    Out-File -FilePath $outputFile -Append -Encoding UTF8

try {
    $camaras = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
        Where-Object { $_.Name -match "Camera|Imaging" -or $_.PNPClass -eq "Image" }

    if ($camaras) {
        $camaras |
            Select-Object Name, Manufacturer, Status, DeviceID, PNPClass |
            Format-List * |
            Out-File -FilePath $outputFile -Append -Encoding UTF8
    }
    else {
        "`tNo se detectó ningún dispositivo de cámara" |
            Out-File -FilePath $outputFile -Append -Encoding UTF8
    }
}
catch {
    "`tError al consultar WMI de cámaras: $($_.Exception.Message)" |
        Out-File -FilePath $outputFile -Append -Encoding UTF8
}
"`n" | Out-File -FilePath $outputFile -Append -Encoding UTF8

# -------------------------------------------------------
# 6. Volcar DxDiag
# -------------------------------------------------------
"## DxDiag completo ##`n" |
    Out-File -FilePath $outputFile -Append -Encoding UTF8

$dxTemp = "$env:TEMP\dxdiag_$timestamp.txt"
& dxdiag /t $dxTemp | Out-Null
Get-Content $dxTemp | Out-File -FilePath $outputFile -Append -Encoding UTF8
Remove-Item $dxTemp -Force

"`n" | Out-File -FilePath $outputFile -Append -Encoding UTF8

# -------------------------------------------------------
# 7. Listado de controladores de cámara instalados
# -------------------------------------------------------
"## Controladores de cámara instalados ##`n" |
    Out-File -FilePath $outputFile -Append -Encoding UTF8

try {
    $drivers = Get-PnpDevice -Class Image -Status OK,Error -ErrorAction Stop
    if ($drivers) {
        $drivers |
            Select-Object InstanceId, FriendlyName, Manufacturer, DriverVersion, Status |
            Format-Table -AutoSize |
            Out-String |
            Out-File -FilePath $outputFile -Append -Encoding UTF8
    }
    else {
        "`tNo se encontraron controladores de cámara instalados" |
            Out-File -FilePath $outputFile -Append -Encoding UTF8
    }
}
catch {
    "`tError al listar controladores de cámara: $($_.Exception.Message)" |
        Out-File -FilePath $outputFile -Append -Encoding UTF8
}
"`n" | Out-File -FilePath $outputFile -Append -Encoding UTF8

# -------------------------------------------------------
# 8. Finalización
# -------------------------------------------------------
"=== Fin de extracción de logs: $(Get-Date) ===" |
    Out-File -FilePath $outputFile -Append -Encoding UTF8

Write-Host "Logs volcados en $outputFile" -ForegroundColor Green
