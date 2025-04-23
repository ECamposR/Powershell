<#
.SYNOPSIS
Lista los controladores (drivers) firmados e instalados que no son de Microsoft.

.DESCRIPTION
Ayuda a identificar drivers de terceros que podrian estar causando inestabilidad.
Muestra el nombre del dispositivo, proveedor, fecha y version del driver.

.NOTES
Ejecutar como Administrador.
Version: 1.0 (Sin caracteres especiales)
#>

Write-Host "--- Listando Drivers de Terceros (No-Microsoft) Instalados ---" -ForegroundColor Cyan

try {
    # Usar Get-CimInstance para obtener drivers firmados (generalmente los mas relevantes)
    # Win32_PnPSignedDriver puede dar mas detalles como fecha y version que Get-WindowsDriver
    $Drivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object { $_.Manufacturer -ne "Microsoft" -and $_.Manufacturer -notlike "*Microsoft*" }

    if ($Drivers) {
        Write-Host "Se encontraron los siguientes drivers de terceros:" -ForegroundColor Green
        $Drivers | Sort-Object DeviceName | Select-Object DeviceName, Manufacturer, DriverVersion, @{Name = 'Fecha Driver'; Expression = { $_.DriverDate } } | Format-Table -AutoSize -Wrap
        Write-Host "`nRevisa si alguno de estos drivers se actualizo recientemente (antes de que empezaran los problemas)"
        Write-Host "Considera actualizar los drivers criticos (Graficos, Red, Chipset) desde la web del fabricante del PC o del componente."
    }
    else {
        Write-Host "No se encontraron drivers firmados de terceros usando Win32_PnPSignedDriver." -ForegroundColor Yellow
        Write-Host "Intentando con Get-WindowsDriver..."
        # Metodo alternativo mas moderno, puede mostrar drivers no firmados tambien
        $DriversAlt = Get-WindowsDriver -Online -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -ne 'Microsoft' }
        if ($DriversAlt) {
            Write-Host "Drivers encontrados con Get-WindowsDriver (puede incluir no firmados):" -ForegroundColor Green
            $DriversAlt | Sort-Object ClassName, ProviderName | Select-Object ClassName, ProviderName, Date, Version | Format-Table -AutoSize -Wrap
        }
        else {
            Write-Host "Tampoco se encontraron drivers de terceros con Get-WindowsDriver." -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Warning "Error al obtener la lista de drivers: $($_.Exception.Message)"
}

Write-Host "`n--- Fin de la lista de drivers ---" -ForegroundColor Cyan