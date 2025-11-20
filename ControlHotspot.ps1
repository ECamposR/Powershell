<#
.SYNOPSIS
    Script para BLOQUEAR/DESBLOQUEAR Mobile Hotspot (Método Híbrido: Servicios + Registro)
    Versión: 3.0 (Nuclear)
#>

# --- BLOQUE DE AUTO-ELEVACIÓN DE PERMISOS ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Reiniciando como Administrador..." -ForegroundColor Yellow
    try {
        Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        Exit
    }
    catch {
        Write-Host "Error: Ejecuta este script manualmente como Administrador." -ForegroundColor Red
        Read-Host "Enter para salir"
        Exit
    }
}

Clear-Host
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   CONTROL TOTAL DE MOBILE HOTSPOT (V3.0)    " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Definición de Objetivos
$Service1 = "icssvc"       # Windows Mobile Hotspot Service
$Service2 = "SharedAccess" # Internet Connection Sharing (ICS)
$RegPath  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections"
$RegName  = "NC_ShowSharedAccessUI"

# 1. Diagnóstico Actual
# Verificamos el estado del servicio principal
$SvcObj = Get-Service -Name $Service1 -ErrorAction SilentlyContinue
$CurrentState = "Desconocido"

if ($SvcObj.StartType -eq "Disabled") {
    $CurrentState = "BLOQUEADO (Servicios Deshabilitados)"
    $Action = "HABILITAR"
    $ColorStatus = "Red"
} else {
    $CurrentState = "HABILITADO (Servicios Activos)"
    $Action = "BLOQUEAR"
    $ColorStatus = "Green"
}

Write-Host "Estado del Sistema: " -NoNewline
Write-Host "$CurrentState" -ForegroundColor $ColorStatus
Write-Host ""

# 2. Interacción
Write-Host "¿Deseas " -NoNewline
Write-Host "$Action" -ForegroundColor Yellow -NoNewline
Write-Host " la funcionalidad de Hotspot?"
$UserResponse = Read-Host "Escribe 'S' para confirmar"

if ($UserResponse -eq 'S') {
    try {
        if ($Action -eq "BLOQUEAR") {
            Write-Host "Aplicando restricciones..." -ForegroundColor Cyan
            
            # A) DETENER Y DESHABILITAR SERVICIOS
            Stop-Service -Name $Service1 -Force -ErrorAction SilentlyContinue
            Stop-Service -Name $Service2 -Force -ErrorAction SilentlyContinue
            Set-Service -Name $Service1 -StartupType Disabled
            Set-Service -Name $Service2 -StartupType Disabled
            Write-Host " [v] Servicios de Hotspot e ICS detenidos y deshabilitados." -ForegroundColor Green

            # B) APLICAR REGISTRO (GPO: Prohibit use of Internet Connection Sharing)
            if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
            # Valor 1 significa "Prohibir/Ocultar UI" en esta política específica
            Set-ItemProperty -Path $RegPath -Name $RegName -Value 1 -Type DWord -Force
            Write-Host " [v] Clave de registro de Política de Grupo aplicada." -ForegroundColor Green
            
            Write-Host ""
            Write-Host "✅ BLOQUEO COMPLETADO." -ForegroundColor Green
            Write-Host "El usuario verá el botón, pero al intentar activarlo dará error o no iniciará." -ForegroundColor Gray
        }
        else {
            Write-Host "Restaurando funcionalidad..." -ForegroundColor Cyan
            
            # A) RESTAURAR SERVICIOS (A Manual, que es el default de Windows)
            Set-Service -Name $Service1 -StartupType Manual
            Set-Service -Name $Service2 -StartupType Manual
            Write-Host " [v] Servicios restaurados a modo Manual." -ForegroundColor Green

            # B) ELIMINAR RESTRICCIÓN DE REGISTRO
            Remove-ItemProperty -Path $RegPath -Name $RegName -ErrorAction SilentlyContinue
            Write-Host " [v] Políticas de restricción eliminadas." -ForegroundColor Green
            
            Write-Host ""
            Write-Host "✅ DESBLOQUEO COMPLETADO." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "❌ ERROR CRÍTICO: " $_.Exception.Message -ForegroundColor Red
        Write-Host "Asegurate de que no hay una GPO de dominio sobreescribiendo esto." -ForegroundColor Red
    }
} else {
    Write-Host "Cancelado." -ForegroundColor Yellow
}

Write-Host ""
Read-Host "Presiona Enter para cerrar..."
