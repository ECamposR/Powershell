<# 
Inventario de hardware (discos y RAM) robusto para Mesh Agent / PS 5.x
- Sin Format-Table; imprime tablas ASCII propias (Print-Table).
- Datos desde CIM/WMI; fallback WMIC si es necesario; Get-Disk/Get-PhysicalDisk opcional.
- Se relanza en 64-bit si detecta proceso 32-bit en SO 64-bit.
#>

$ErrorActionPreference = 'SilentlyContinue'

# --- Relanzar en 64-bit si el proceso actual es 32-bit en SO 64-bit ---
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $sysNativePwsh = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path $sysNativePwsh) {
        & $sysNativePwsh -ExecutionPolicy Bypass -File $PSCommandPath @args
        exit $LASTEXITCODE
    }
}

# --- Modulo Storage (opcional) para Get-PhysicalDisk ---
try {
    if (Get-Module -ListAvailable -Name Storage | Select-Object -First 1) {
        Import-Module Storage -ErrorAction SilentlyContinue | Out-Null
    }
} catch { }

# --- Utiles ---
function Convert-Bytes {
    param([UInt64]$Bytes)
    if ($Bytes -ge 1TB) { '{0:N2} TB' -f ($Bytes / 1TB) }
    elseif ($Bytes -ge 1GB) { '{0:N2} GB' -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { '{0:N2} MB' -f ($Bytes / 1MB) }
    else { '{0:N0} B' -f $Bytes }
}
function Normalize-String { param([string]$s) if ([string]::IsNullOrWhiteSpace($s)) { return $null } ($s -replace '\s+', ' ').Trim() }
function Get-Prop { param($obj,[string]$name) if (-not $obj) { return $null } $p = $obj.PSObject.Properties.Match($name); if ($p -and $p.Count -gt 0) { $p[0].Value } }

# Tabla ASCII simple, fiable
function Print-Table {
    param([Parameter(Mandatory=$true)][Object[]]$Data,[Parameter(Mandatory=$true)][string[]]$Columns,[int]$MaxColWidth=60)
    $rows = @($Data); if ($rows.Count -eq 0) { return }
    $widths = @()
    foreach ($col in $Columns) {
        $max = [Math]::Min($MaxColWidth, $col.Length)
        foreach ($r in $rows) {
            $val = [string](Get-Prop $r $col); if ($null -eq $val) { $val = '' }
            $len = [Math]::Min($MaxColWidth, $val.Length)
            if ($len -gt $max) { $max = $len }
        }
        $widths += $max
    }
    $line = ''; for ($i=0; $i -lt $Columns.Count; $i++) { $line += $Columns[$i].PadRight($widths[$i]+2) }; Write-Host $line
    $sep  = ''; for ($i=0; $i -lt $Columns.Count; $i++) { $sep  += ('-'*$widths[$i]).PadRight($widths[$i]+2,'-') }; Write-Host $sep
    foreach ($r in $rows) {
        $line = ''
        for ($i=0; $i -lt $Columns.Count; $i++) {
            $v = [string](Get-Prop $r $Columns[$i]); if ($null -eq $v) { $v = '' }
            if ($v.Length -gt $MaxColWidth) { $v = $v.Substring(0,$MaxColWidth) }
            $line += $v.PadRight($widths[$i]+2)
        }
        Write-Host $line
    }
}

# --- Wrappers de datos ---
function Get-ByCimOrWmi {
    param([string]$Class,[string]$Namespace='root\cimv2')
    $items = @()
    try { $items = Get-CimInstance -ClassName $Class -Namespace $Namespace -ErrorAction Stop } catch { }
    if (-not $items -or @($items).Count -eq 0) { try { $items = Get-WmiObject -Class $Class -Namespace $Namespace -ErrorAction Stop } catch { } }
    if ($items) { $items } else { @() }
}
function Get-FromWMIC {
    param([Parameter(Mandatory=$true)][string]$Alias,[string[]]$Fields)
    $exe = Join-Path $env:WINDIR 'System32\wbem\wmic.exe'
    if (-not (Test-Path $exe)) { return @() }
    $cmd = "$Alias get " + ($Fields -join ',') + " /format:csv"
    try {
        $raw = & $exe $cmd 2>$null
        if (-not $raw) { return @() }
        $lines = $raw | Where-Object { $_ -and $_.Trim().Length -gt 0 }
        $csv = $lines -join [Environment]::NewLine
        $parsed = $csv | ConvertFrom-Csv
        if ($parsed) { $parsed } else { @() }
    } catch { @() }
}
function Get-PhysicalDiskSafe { try { Get-PhysicalDisk -ErrorAction Stop } catch { @() } }

# --- Discos: CIM/WMI -> Get-Disk/PhysicalDisk -> WMIC (fallback) ---
function Get-DisksInfo {
    $cimDisks = Get-ByCimOrWmi -Class 'Win32_DiskDrive' | Sort-Object Index
    $gdDisks  = @(); try { $gdDisks = Get-Disk | Sort-Object Number } catch { }
    $pdDisks  = Get-PhysicalDiskSafe

    if (@($cimDisks).Count -eq 0) {
        $wm = Get-FromWMIC -Alias 'diskdrive' -Fields @('Model','SerialNumber','Size','Manufacturer','InterfaceType','FirmwareRevision','Index')
        if (@($wm).Count -gt 0) {
            $cimDisks = foreach ($r in $wm) {
                [PSCustomObject]@{
                    Index            = [int]($r.Index)
                    Model            = $r.Model
                    SerialNumber     = $r.SerialNumber
                    Size             = [UInt64]($r.Size)
                    Manufacturer     = $r.Manufacturer
                    InterfaceType    = $r.InterfaceType
                    FirmwareRevision = $r.FirmwareRevision
                    TotalSectors     = $null
                    BytesPerSector   = $null
                }
            }
        }
    }

    $gdIndex = @{}; foreach ($gd in $gdDisks) { $gdIndex[$gd.Number] = $gd }
    $pdBySerial = @{}; foreach ($pd in $pdDisks) { $sn = Get-Prop $pd 'SerialNumber'; if ($sn) { $pdBySerial[$sn.Trim()] = $pd } }

    $result = foreach ($d in $cimDisks) {
        $diskNumber = Get-Prop $d 'Index'
        $gd = $gdIndex[$diskNumber]

        # Serial candidates
        $serial = $null
        foreach ($c in @((Get-Prop $d 'SerialNumber'), (Get-Prop $gd 'SerialNumber'))) { if ($c -and $c.Trim()) { $serial = $c.Trim(); break } }

        # Vinculo PhysicalDisk
        $pd = $null
        if ($serial -and $pdBySerial.ContainsKey($serial)) { $pd = $pdBySerial[$serial] }
        elseif ($pdDisks -and (Get-Prop $d 'Model')) {
            $model = (Get-Prop $d 'Model').Trim()
            $pd = $pdDisks | Where-Object { (Get-Prop $_ 'FriendlyName') -and ((Get-Prop $_ 'FriendlyName').Trim() -eq $model) } | Select-Object -First 1
        }

        # Tipo
        $mediaTypeStr = $null; $spindle = $null; $health = $null
        if ($pd) {
            $spindle = Get-Prop $pd 'SpindleSpeed'
            $health  = Get-Prop $pd 'HealthStatus'
            $mt = Get-Prop $pd 'MediaType'
            if ($mt) {
                $mts = $mt.ToString()
                if ($mts -match 'SSD') { $mediaTypeStr = 'SSD' }
                elseif ($mts -match 'HDD') { $mediaTypeStr = 'HDD' }
            }
        }
        if (-not $mediaTypeStr) {
            $bus = $null
            if ($gd -and (Get-Prop $gd 'BusType')) { $bus = (Get-Prop $gd 'BusType').ToString() }
            elseif (Get-Prop $d 'InterfaceType') { $bus = Get-Prop $d 'InterfaceType' }
            $model = Get-Prop $d 'Model'
            if ($bus -eq 'NVMe' -or ($model -and $model -match 'NVMe|NVME')) { $mediaTypeStr = 'SSD (NVMe)' }
            elseif ($model -and $model -match 'SSD') { $mediaTypeStr = 'SSD' }
            elseif ($spindle -and $spindle -gt 0) { $mediaTypeStr = 'HDD' }
            else { $mediaTypeStr = 'Desconocido' }
        }

        $busType = $null
        if ($gd -and (Get-Prop $gd 'BusType')) { $busType = (Get-Prop $gd 'BusType').ToString() }
        elseif (Get-Prop $d 'InterfaceType') { $busType = Get-Prop $d 'InterfaceType' }

        $fw = $null
        $fw1 = Get-Prop $pd 'FirmwareVersion'; $fw2 = Get-Prop $d 'FirmwareRevision'
        if ($fw1) { $fw = $fw1 } elseif ($fw2) { $fw = $fw2 }

        $size = 0; $sz = Get-Prop $d 'Size'; if ($sz) { $size = [UInt64]$sz }

        $mfg = Normalize-String (Get-Prop $d 'Manufacturer')
        if (-not $mfg -and (Get-Prop $d 'Model')) {
            $parts = (Get-Prop $d 'Model') -split '\s+'
            if ($parts.Count -gt 0) {
                $cand = $parts[0]; if ($cand -notmatch 'Generic|Microsoft|Disk') { $mfg = $cand }
            }
        }

        [PSCustomObject]@{
            'Disco #'         = $diskNumber
            'Tipo'            = $mediaTypeStr
            'Marca'           = Normalize-String $mfg
            'Modelo'          = Normalize-String (Get-Prop $d 'Model')
            'Numero de serie' = Normalize-String $serial
            'Firmware'        = Normalize-String $fw
            'Bus/Interfaz'    = Normalize-String $busType
            'Capacidad'       = Convert-Bytes $size
            'Sectores'        = if (Get-Prop $d 'TotalSectors') { '{0:N0}' -f (Get-Prop $d 'TotalSectors') } else { $null }
            'Tamano sector'   = if (Get-Prop $d 'BytesPerSector') { '{0:N0} B' -f (Get-Prop $d 'BytesPerSector') } else { $null }
            'Estado'          = if ($health) { $health.ToString() } else { $null }
        }
    }

    if (@($result).Count -eq 0) {
        $wm = Get-FromWMIC -Alias 'diskdrive' -Fields @('Model','SerialNumber','Size','Manufacturer','InterfaceType','FirmwareRevision','Index')
        $result = foreach ($r in $wm) {
            $model = $r.Model; $bus = $r.InterfaceType; $tipo = 'Desconocido'
            if ($model -match 'NVMe|NVME') { $tipo = 'SSD (NVMe)' }
            elseif ($model -match 'SSD') { $tipo = 'SSD' }
            [PSCustomObject]@{
                'Disco #'         = [int]$r.Index
                'Tipo'            = $tipo
                'Marca'           = Normalize-String $r.Manufacturer
                'Modelo'          = Normalize-String $model
                'Numero de serie' = Normalize-String $r.SerialNumber
                'Firmware'        = Normalize-String $r.FirmwareRevision
                'Bus/Interfaz'    = Normalize-String $bus
                'Capacidad'       = Convert-Bytes ([UInt64]$r.Size)
                'Sectores'        = $null
                'Tamano sector'   = $null
                'Estado'          = $null
            }
        }
    }

    $result
}

# --- RAM: CIM/WMI -> WMIC (fallback) ---
function Get-RAMInfo {
    $memModules = Get-ByCimOrWmi -Class 'Win32_PhysicalMemory' | Sort-Object BankLabel, DeviceLocator
    $memArray   = Get-ByCimOrWmi -Class 'Win32_PhysicalMemoryArray' | Select-Object -First 1

    if (@($memModules).Count -eq 0) {
        $wm = Get-FromWMIC -Alias 'memorychip' -Fields @('BankLabel','DeviceLocator','Capacity','Manufacturer','PartNumber','SerialNumber','Speed','SMBIOSMemoryType','FormFactor','ConfiguredClockSpeed','ConfiguredVoltage')
        $memModules = foreach ($r in $wm) {
            [PSCustomObject]@{
                BankLabel            = $r.BankLabel
                DeviceLocator        = $r.DeviceLocator
                Capacity             = [UInt64]$r.Capacity
                Manufacturer         = $r.Manufacturer
                PartNumber           = $r.PartNumber
                SerialNumber         = $r.SerialNumber
                Speed                = if ($r.Speed) { [int]$r.Speed } else { $null }
                SMBIOSMemoryType     = if ($r.SMBIOSMemoryType) { [int]$r.SMBIOSMemoryType } else { $null }
                FormFactor           = if ($r.FormFactor) { [int]$r.FormFactor } else { $null }
                ConfiguredClockSpeed = if ($r.ConfiguredClockSpeed) { [int]$r.ConfiguredClockSpeed } else { $null }
                ConfiguredVoltage    = if ($r.ConfiguredVoltage) { [int]$r.ConfiguredVoltage } else { $null }
            }
        }
        $memArray = $null
    }

    $rows = foreach ($m in $memModules) {
        $cap  = Get-Prop $m 'Capacity'
        $spd  = Get-Prop $m 'Speed'
        $cfgS = Get-Prop $m 'ConfiguredClockSpeed'
        $ff   = Get-Prop $m 'FormFactor'
        $ddrt = Get-Prop $m 'SMBIOSMemoryType'
        $bankOrSlot = $null
        $b = Get-Prop $m 'BankLabel'; $d = Get-Prop $m 'DeviceLocator'
        if ($b -and $b.Trim()) { $bankOrSlot = $b } elseif ($d -and $d.Trim()) { $bankOrSlot = $d }
        $form = $null
        if ($ff -eq 8) { $form = 'DIMM' } elseif ($ff -eq 12) { $form = 'SODIMM' } elseif ($ff) { $form = ('FF#{0}' -f $ff) }
        $ddr = $null
        if ($ddrt -eq 34) { $ddr = 'DDR5' } elseif ($ddrt -eq 26) { $ddr = 'DDR4' } elseif ($ddrt -eq 24) { $ddr = 'DDR3' }

        [PSCustomObject]@{
            'Banco/Slot'            = Normalize-String $bankOrSlot
            'Fabricante'            = Normalize-String (Get-Prop $m 'Manufacturer')
            'PN (PartNumber)'       = Normalize-String ((Get-Prop $m 'PartNumber') -replace '\s+$')
            'Serie'                 = Normalize-String (Get-Prop $m 'SerialNumber')
            'Capacidad'             = if ($cap)  { '{0:N2} GB' -f ($cap/1GB) } else { $null }
            'Velocidad'             = if ($spd)  { '{0} MT/s' -f $spd } else { $null }
            'Velocidad Configurada' = if ($cfgS) { '{0} MT/s' -f $cfgS } else { $null }
            'Tipo (DDR)'            = $ddr
            'Form Factor'           = $form
            'Voltaje (Config)'      = if (Get-Prop $m 'ConfiguredVoltage') { '{0:N3} V' -f ((Get-Prop $m 'ConfiguredVoltage')/1000) } else { $null }
        }
    }

    $totalInstalled = (@($memModules) | Measure-Object -Property Capacity -Sum).Sum
    if (-not $totalInstalled) { $totalInstalled = 0 }

    $slotsTotal  = $null
    $maxCapBytes = $null
    if ($memArray) {
        $slotsTotal = Get-Prop $memArray 'MemoryDevices'
        $mcex = Get-Prop $memArray 'MaxCapacityEx'
        $mc   = Get-Prop $memArray 'MaxCapacity'
        if ($mcex -and $mcex -gt 0) { $maxCapBytes = [UInt64]$mcex }
        elseif ($mc -and $mc -gt 0) { $maxCapBytes = [UInt64]$mc * 1024 }
    }
    # Corregir valores irreales de MaxCapacity y estimar si es posible
    if ($maxCapBytes -and $maxCapBytes -lt $totalInstalled) { $maxCapBytes = $null }
    if (-not $maxCapBytes -and $slotsTotal -and @($memModules).Count -gt 0) {
        $largest = (@($memModules) | Measure-Object -Property Capacity -Maximum).Maximum
        if ($largest -and $largest -gt 0) { $maxCapBytes = [UInt64]$largest * [UInt64]$slotsTotal }
    }

    [PSCustomObject]@{
        Modules = $rows
        Summary = [PSCustomObject]@{
            'Modulos instalados'                       = @($memModules).Count
            'Slots totales (si reporta)'               = $slotsTotal
            'Capacidad instalada'                      = Convert-Bytes $totalInstalled
            'Capacidad maxima soportada (si reporta)'  = if ($maxCapBytes) { Convert-Bytes $maxCapBytes } else { $null }
        }
    }
}

# --- Cabecera ---
$computer = $env:COMPUTERNAME
$os = (Get-ByCimOrWmi -Class 'Win32_OperatingSystem' | Select-Object -First 1)
$cs = (Get-ByCimOrWmi -Class 'Win32_ComputerSystem' | Select-Object -First 1)

Write-Host ('='*78)
Write-Host ("INVENTARIO RAPIDO DE HARDWARE - {0}" -f $computer)
if ($os -and $cs) { Write-Host ("Equipo: {0}  |  Usuario: {1}  |  SO: {2} {3}" -f ($cs.Model), $env:USERNAME, $os.Caption, $os.Version) }
Write-Host ('='*78)
Write-Host ""

# --- Discos ---
Write-Host "ALMACENAMIENTO (Discos Fisicos)"
$disks = Get-DisksInfo
if (@($disks).Count -gt 0) {
    Print-Table -Data @($disks) -Columns @('Disco #','Tipo','Marca','Modelo','Numero de serie','Firmware','Bus/Interfaz','Capacidad','Sectores','Tamano sector','Estado')
} else {
    Write-Host "No se encontraron discos fisicos o no fue posible obtener la informacion."
}
Write-Host ""

# --- RAM ---
Write-Host "MEMORIA RAM (Modulos instalados)"
$ramInfo = Get-RAMInfo
if ($ramInfo -and @($ramInfo.Modules).Count -gt 0) {
    Print-Table -Data @($ramInfo.Modules) -Columns @('Banco/Slot','Fabricante','PN (PartNumber)','Serie','Capacidad','Velocidad','Velocidad Configurada','Tipo (DDR)','Form Factor','Voltaje (Config)')
} else {
    Write-Host "No se encontraron modulos de memoria o no fue posible obtener la informacion."
}
Write-Host ""

# --- RESUMEN ---
Write-Host "RESUMEN DE MEMORIA"
if ($ramInfo -and $ramInfo.Summary) {
    $sum = $ramInfo.Summary
    $summaryRows = @(
        [pscustomobject]@{ Clave = 'Modulos instalados';                      Valor = [string](Get-Prop $sum 'Modulos instalados') },
        [pscustomobject]@{ Clave = 'Slots totales (si reporta)';              Valor = [string](Get-Prop $sum 'Slots totales (si reporta)') },
        [pscustomobject]@{ Clave = 'Capacidad instalada';                     Valor = [string](Get-Prop $sum 'Capacidad instalada') },
        [pscustomobject]@{ Clave = 'Capacidad maxima soportada (si reporta)'; Valor = [string](Get-Prop $sum 'Capacidad maxima soportada (si reporta)') }
    )
    Print-Table -Data $summaryRows -Columns @('Clave','Valor') -MaxColWidth 80
} else {
    Write-Host "Sin datos de resumen de memoria."
}

Write-Host ""
Write-Host ('-'*78)
Write-Host "Para guardar en archivo (texto plano):"
Write-Host "  powershell -ExecutionPolicy Bypass -File .\hardware.ps1 | Out-File .\inventario_$(Get-Date -Format yyyyMMdd_HHmm).txt -Encoding UTF8"
Write-Host ('-'*78)

