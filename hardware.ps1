<#
.SYNOPSIS
    Script para obtener información de hardware y software en Windows 11.
.DESCRIPTION
    Recopila datos de:
      - Procesador (nombre, núcleos, hilos, velocidad)
      - Memoria RAM total
      - Almacenamiento (tamaño y espacio libre de discos)
      - Placa base (fabricante, modelo, serial)
      - BIOS (fabricante, versión, fecha)
      - GPU (adaptador y memoria)
      - Número de serie / Service Tag y UUID del equipo
      - Windows (nombre, versión, compilación y fecha de instalación)
    Presenta la salida de forma clara y estructurada en español.
.NOTES
    Asegúrate de guardar este archivo como UTF-8 con BOM para respetar los caracteres acentuados.
#>

# Forzar codificación UTF-8 en la salida
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Procesador
$cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1 `
@{Name = 'Name'; Expression = { $_.Name.Trim() } }, `
@{Name = 'Cores'; Expression = { $_.NumberOfCores } }, `
@{Name = 'Threads'; Expression = { $_.NumberOfLogicalProcessors } }, `
@{Name = 'MaxClockMHz'; Expression = { $_.MaxClockSpeed } }

# Memoria RAM total (GB)
$ramInfo = Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
$ramTotalGB = [math]::Round($ramInfo.Sum / 1GB, 2)

# Almacenamiento (discos locales)
$disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | Select-Object `
@{Name = 'Drive'; Expression = { $_.DeviceID } }, `
@{Name = 'SizeGB'; Expression = { [math]::Round($_.Size / 1GB, 2) } }, `
@{Name = 'FreeGB'; Expression = { [math]::Round($_.FreeSpace / 1GB, 2) } }

# Placa base
$board = Get-CimInstance -ClassName Win32_BaseBoard | Select-Object `
@{Name = 'Manufacturer'; Expression = { $_.Manufacturer } }, `
@{Name = 'Product'; Expression = { $_.Product } }, `
@{Name = 'SerialNumber'; Expression = { $_.SerialNumber } }

# BIOS
$bios = Get-CimInstance -ClassName Win32_BIOS | Select-Object `
@{Name = 'Manufacturer'; Expression = { $_.Manufacturer } }, `
@{Name = 'Version'; Expression = { $_.SMBIOSBIOSVersion } }, `
@{Name = 'ReleaseDate'; Expression = { ([Management.ManagementDateTimeConverter]::ToDateTime($_.ReleaseDate)).ToString('yyyy-MM-dd') } }

# GPU
$gpus = Get-CimInstance -ClassName Win32_VideoController | Select-Object `
@{Name = 'Name'; Expression = { $_.Name } }, `
@{Name = 'MemoryMB'; Expression = { [math]::Round($_.AdapterRAM / 1MB, 0) } }

# Service Tag y UUID
$system = Get-CimInstance -ClassName Win32_ComputerSystemProduct | Select-Object `
@{Name = 'ServiceTag'; Expression = { $_.IdentifyingNumber } }, `
@{Name = 'UUID'; Expression = { $_.UUID } }

# Información de Windows
$os = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object `
@{Name = 'Caption'; Expression = { $_.Caption } }, `
@{Name = 'Version'; Expression = { $_.Version } }, `
@{Name = 'BuildNumber'; Expression = { $_.BuildNumber } }, `
@{Name = 'InstallDate'; Expression = { ([Management.ManagementDateTimeConverter]::ToDateTime($_.InstallDate)).ToString('yyyy-MM-dd') } }

# Construir objeto de salida con etiquetas en español
$result = [PSCustomObject]@{
    'Procesador'      = $cpu.Name
    'Núcleos (cores)' = $cpu.Cores
    'Hilos (threads)' = $cpu.Threads
    'Velocidad (MHz)' = $cpu.MaxClockMHz
    'RAM total (GB)'  = $ramTotalGB
    'Discos'          = ($disks | ForEach-Object { "$_: $($_.SizeGB) GB ($($_.FreeGB) GB libres)" }) -join '; '
    'Placa base'      = "$($board.Manufacturer) $($board.Product) (S/N: $($board.SerialNumber))"
    'BIOS'            = "$($bios.Manufacturer) v$($bios.Version) (Fecha: $($bios.ReleaseDate))"
    'GPU'             = ($gpus | ForEach-Object { "$($_.Name) - $($_.MemoryMB) MB" }) -join '; '
    'Service Tag'     = $system.ServiceTag
    'UUID'            = $system.UUID
    'Windows'         = "$($os.Caption) v$($os.Version) (Build $($os.BuildNumber)) instalado el $($os.InstallDate)"
}

# Mostrar resultado en lista
$result | Format-List
