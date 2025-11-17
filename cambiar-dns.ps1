<#
.SYNOPSIS
Cambia los servidores DNS de un equipo unido a dominio a Cloudflare o al DNS del dominio.

.DESCRIPTION
El script:
- Verifica si se ejecuta con privilegios de administrador.
- Si no, solicita credenciales y se relanza con esas credenciales.
- Pregunta qué DNS configurar: Cloudflare (1.1.1.1) o DNS del dominio (192.168.2.2).
- Permite elegir la interfaz de red activa (con IPv4 y en estado Up) donde aplicar el cambio.
#>

param(
    [switch]$SkipElevation
)

function Test-Admin {
    $currentId = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentId)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# 1. Comprobar si se ejecuta como administrador, si no, pedir credenciales y relanzar
if (-not $SkipElevation) {
    if (-not (Test-Admin)) {
        Write-Host "Este script debe ejecutarse con privilegios de administrador.`n"
        $cred = Get-Credential -Message "Introduce credenciales con permisos de administrador local o de dominio"
        if (-not $cred) {
            Write-Error "No se proporcionaron credenciales. Saliendo."
            exit 1
        }

        $psiArgs = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$PSCommandPath`"",
            "-SkipElevation"
        )

        Start-Process -FilePath "powershell.exe" -Credential $cred -ArgumentList $psiArgs
        exit
    }
}

Write-Host "Cambiando DNS de este equipo." -ForegroundColor Cyan
Write-Host ""

# 2. Preguntar qué DNS se quiere usar
Write-Host "Selecciona la opcion de DNS:"
Write-Host "  1 - Cloudflare 1.1.1.1"
Write-Host "  2 - DNS del dominio 192.168.2.2"
$opcion = Read-Host "Escribe 1 o 2"

switch ($opcion) {
    "1" {
        $dnsNuevo = @("1.1.1.1")
        $descripcion = "Cloudflare"
    }
    "2" {
        $dnsNuevo = @("192.168.2.2")
        $descripcion = "DNS del dominio"
    }
    default {
        Write-Error "Opcion no valida. Saliendo."
        exit 1
    }
}

Write-Host ""
Write-Host "Buscando interfaces de red activas..." -ForegroundColor Cyan

# 3. Obtener interfaces con IPv4 y estado Up (más robusto que -Physical)
$interfaces = Get-NetIPConfiguration |
    Where-Object {
        $_.IPv4Address -and
        $_.NetAdapter.Status -eq 'Up'
    }

if (-not $interfaces) {
    Write-Error "No se encontraron interfaces de red activas con IPv4."
    exit 1
}

Write-Host "Interfaces disponibles:"
for ($i = 0; $i -lt $interfaces.Count; $i++) {
    $idx = $i + 1
    $ip  = $interfaces[$i].IPv4Address.IPAddress
    $name = $interfaces[$i].InterfaceAlias
    $desc = $interfaces[$i].NetAdapter.InterfaceDescription
    Write-Host ("  {0} - {1} ({2}) IP: {3}" -f $idx, $name, $desc, $ip)
}

$sel = Read-Host "Selecciona el numero de la interfaz donde quieres aplicar el cambio"

[int]$selNum = 0
if (-not [int]::TryParse($sel, [ref]$selNum) -or $selNum -lt 1 -or $selNum -gt $interfaces.Count) {
    Write-Error "Seleccion no valida. Saliendo."
    exit 1
}

$intf = $interfaces[$selNum - 1]

Write-Host ""
Write-Host "Aplicando DNS $descripcion [$($dnsNuevo -join ", ")] en la interfaz '$($intf.InterfaceAlias)' ..." -ForegroundColor Yellow

# 4. Aplicar DNS nuevo
try {
    Set-DnsClientServerAddress -InterfaceAlias $intf.InterfaceAlias -ServerAddresses $dnsNuevo -ErrorAction Stop
    Write-Host "DNS actualizado correctamente." -ForegroundColor Green
} catch {
    Write-Error "Error al cambiar los DNS: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "Configuracion actual de DNS en la interfaz seleccionada:" -ForegroundColor Cyan
Get-DnsClientServerAddress -InterfaceAlias $intf.InterfaceAlias -AddressFamily IPv4

