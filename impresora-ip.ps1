<#
    Script: Crear impresora local por IP para Canon iR-ADV C359
    - Crea puerto TCP/IP a 192.168.2.14
    - Crea una impresora local usando el driver Canon ya instalado
#>

# 1. Verificar que se ejecuta como administrador
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Ejecuta este script en una consola de PowerShell con privilegios de administrador."
    exit 1
}

# 2. IP y nombre que tendrá la nueva impresora
$printerIP   = "192.168.2.14"
$portName    = "IP_$printerIP"
$printerName = "iR-ADV C359 IP"

# 3. Localizar el driver de Canon ya instalado
#    Ajusta el patrón según lo que te devolvió Get-PrinterDriver.
$driverPattern = "Canon Generic Plus PS3"

$driver = Get-PrinterDriver | Where-Object { $_.Name -like $driverPattern } | Select-Object -First 1

if (-not $driver) {
    Write-Error "No se encontró ningún driver que coincida con '$driverPattern'. Revisa 'Get-PrinterDriver | Select Name' y ajusta el patrón."
    exit 1
}

Write-Host "Usando driver: $($driver.Name)"

# 4. Crear el puerto TCP/IP si no existe
if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
    Write-Host "Creando puerto TCP/IP '$portName' para la IP $printerIP ..."
    Add-PrinterPort -Name $portName -PrinterHostAddress $printerIP
} else {
    Write-Host "El puerto '$portName' ya existe. Se reutilizará."
}

# 5. Crear la impresora local si aún no existe
if (-not (Get-Printer -Name $printerName -ErrorAction SilentlyContinue)) {
    Write-Host "Creando impresora local '$printerName' en el puerto $portName ..."
    Add-Printer -Name $printerName -DriverName $driver.Name -PortName $portName
} else {
    Write-Host "La impresora '$printerName' ya existe. No se vuelve a crear."
}

Write-Host "Listo. La impresora '$printerName' debería aparecer ahora en 'Impresoras y escáneres' y apuntar directo a $printerIP."
Write-Host "Haz una prueba de impresión con esa impresora nueva."

