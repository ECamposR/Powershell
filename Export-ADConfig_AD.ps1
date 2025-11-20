<#
.SYNOPSIS
    Exporta información básica de Active Directory (bosque, dominio,
    controladores de dominio y OUs) a archivos de texto para documentación.

.DESCRIPTION
    Crea una carpeta con timestamp dentro de $OutputRoot y genera:
      - AD_ReporteGeneral.txt  -> resumen bosque/dominio/DCs
      - AD_OUs.txt             -> listado detallado de OUs

.PARAMETER OutputRoot
    Carpeta raíz donde se guardarán los reportes.

.PARAMETER IncludeOUAcl
    Si se especifica, intentará exportar también un resumen de ACL
    de las OUs (puede generar archivos grandes).

.NOTES
    Probar primero en lab. Requiere módulo ActiveDirectory.
#>

[CmdletBinding()]
param(
    [string]$OutputRoot = "C:\AD_Documentacion",
    [switch]$IncludeOUAcl
)

# 1. Cargar módulo de AD
try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "No se pudo cargar el módulo ActiveDirectory. ¿Estás en un DC o con RSAT instalado?"
    return
}

# 2. Preparar carpeta de salida
$now       = Get-Date
$timestamp = $now.ToString("yyyyMMdd-HHmmss")

# Obtenemos algo de contexto del dominio
try {
    $domain = Get-ADDomain -ErrorAction Stop
}
catch {
    Write-Error "No se pudo obtener información del dominio. Verifica conectividad y permisos."
    return
}

$forest = Get-ADForest
$server = $env:COMPUTERNAME
$domainName = $domain.DNSRoot

$folderName = "{0}_{1}_{2}" -f $domainName, $server, $timestamp
$OutputPath = Join-Path -Path $OutputRoot -ChildPath $folderName

if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# 3. Archivos de salida
$ReportFile = Join-Path $OutputPath "AD_ReporteGeneral.txt"
$OuFile     = Join-Path $OutputPath "AD_OUs.txt"

function Add-ReportLine {
    param(
        [string]$Text = ""
    )
    $Text | Out-File -FilePath $ReportFile -Append -Encoding UTF8
}

function Add-OuLine {
    param(
        [string]$Text = ""
    )
    $Text | Out-File -FilePath $OuFile -Append -Encoding UTF8
}

# 4. Encabezado del reporte general
Add-ReportLine "# Reporte de configuración Active Directory (AD DS)"
Add-ReportLine ""
Add-ReportLine "Fecha de generación : $($now)"
Add-ReportLine "Servidor que ejecutó : $server"
Add-ReportLine "Dominio               : $domainName"
Add-ReportLine "Bosque                : $($forest.RootDomain)"
Add-ReportLine "Carpeta de salida     : $OutputPath"
Add-ReportLine ""
Add-ReportLine "=================================================="
Add-ReportLine ""

# 5. Información del bosque
Add-ReportLine "## Información del bosque"
Add-ReportLine ""

$forestInfo = $forest |
    Select-Object RootDomain,
                  ForestMode,
                  Domains,
                  GlobalCatalogs,
                  SchemaMaster,
                  DomainNamingMaster

$forestTxt = $forestInfo | Format-List | Out-String
Add-ReportLine $forestTxt.TrimEnd()
Add-ReportLine ""
Add-ReportLine "--------------------------------------------------"
Add-ReportLine ""

# 6. Información del dominio
Add-ReportLine "## Información del dominio"
Add-ReportLine ""

$domainInfo = $domain |
    Select-Object DNSRoot,
                  NetBIOSName,
                  DomainMode,
                  InfrastructureMaster,
                  RIDMaster,
                  PDCEmulator,
                  ParentDomain,
                  ChildDomains,
                  ReplicaDirectoryServers

$domainTxt = $domainInfo | Format-List | Out-String
Add-ReportLine $domainTxt.TrimEnd()
Add-ReportLine ""
Add-ReportLine "--------------------------------------------------"
Add-ReportLine ""

# 7. Controladores de dominio
Add-ReportLine "## Controladores de dominio"
Add-ReportLine ""

$dcs = Get-ADDomainController -Filter * |
    Sort-Object HostName

if ($dcs) {
    $dcsInfo = $dcs |
        Select-Object HostName,
                      IPv4Address,
                      Site,
                      IsGlobalCatalog,
                      IsReadOnly,
                      Enabled,
                      OperatingSystem,
                      OperatingSystemVersion

    $dcsTxt = $dcsInfo | Format-Table -AutoSize | Out-String
    Add-ReportLine $dcsTxt.TrimEnd()
}
else {
    Add-ReportLine "No se encontraron controladores de dominio (algo raro pasa aquí)."
}
Add-ReportLine ""
Add-ReportLine "--------------------------------------------------"
Add-ReportLine ""

# 8. OUs (estructura básica)
Add-ReportLine "## Unidades organizativas (resumen)"
Add-ReportLine ""
Add-ReportLine "El detalle completo de OUs se encuentra en: $OuFile"
Add-ReportLine ""

Add-OuLine "# Listado de Unidades Organizativas (OUs)"
Add-OuLine ""
Add-OuLine "Fecha de generación : $($now)"
Add-OuLine "Dominio             : $domainName"
Add-OuLine ""
Add-OuLine "=================================================="
Add-OuLine ""

$ous = Get-ADOrganizationalUnit -Filter * -Properties ProtectedFromAccidentalDeletion |
    Sort-Object DistinguishedName

foreach ($ou in $ous) {
    Add-OuLine "Nombre              : $($ou.Name)"
    Add-OuLine "DistinguishedName   : $($ou.DistinguishedName)"
    Add-OuLine "Protegida contra borrado accidental : $($ou.ProtectedFromAccidentalDeletion)"
    Add-OuLine ""
}

Add-OuLine "Total de OUs: $($ous.Count)"

Add-ReportLine "Total de OUs encontradas: $($ous.Count)"
Add-ReportLine ""

# 9. (Opcional) Exportar ACL de OUs (puede ser muy verboso)
if ($IncludeOUAcl.IsPresent) {
    $OuAclFile = Join-Path $OutputPath "AD_OU_ACL.txt"
    "## ACL de OUs (delegaciones de permisos)" | Out-File -FilePath $OuAclFile -Encoding UTF8
    "" | Out-File -FilePath $OuAclFile -Append -Encoding UTF8

    $index = 0
    foreach ($ou in $ous) {
        $index++
        Write-Host "Exportando ACL de OU [$index/$($ous.Count)]: $($ou.DistinguishedName)"

        Add-Content -Path $OuAclFile -Value ("OU: {0}" -f $ou.DistinguishedName)
        Add-Content -Path $OuAclFile -Value ("Nombre: {0}" -f $ou.Name)

        try {
            $acl = Get-Acl -Path ("AD:{0}" -f $ou.DistinguishedName)
            $aclTxt = $acl | Format-List | Out-String
            Add-Content -Path $OuAclFile -Value $aclTxt.TrimEnd()
        }
        catch {
            Add-Content -Path $OuAclFile -Value "Error al obtener ACL: $($_.Exception.Message)"
        }

        Add-Content -Path $OuAclFile -Value ""
        Add-Content -Path $OuAclFile -Value "--------------------------------------------------"
        Add-Content -Path $OuAclFile -Value ""
    }

    Add-ReportLine "Se generó archivo de ACL de OUs: $OuAclFile"
    Add-ReportLine ""
}

Add-ReportLine "Fin del módulo de AD DS (bosque/dominio/DCs/OUs)."
Add-ReportLine "Siguiente fase sugerida: DNS, DHCP, WSUS, GPO."
Add-ReportLine ""
Add-ReportLine "=================================================="
Add-ReportLine "Fin del reporte generado por este módulo."

