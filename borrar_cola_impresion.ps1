# Este script detiene el servicio de cola de impresión, borra todos los trabajos pendientes y reinicia el servicio.

# Detener el servicio de cola de impresión
try {
    Stop-Service -Name spooler -Force -ErrorAction Stop
    Write-Output "Servicio de cola de impresión detenido."
} catch {
    Write-Output "Error al detener el servicio de cola de impresión: $_"
    exit 1
}

# Eliminar todos los archivos en la carpeta de impresión
try {
    $printPath = "$env:windir\System32\spool\PRINTERS\*.*"
    Remove-Item -Path $printPath -Force -ErrorAction Stop
    Write-Output "Cola de impresión limpiada."
} catch {
    Write-Output "Error al limpiar la cola de impresión: $_"
    # Intentamos reiniciar el servicio antes de salir, incluso si falla la limpieza de archivos
    Start-Service -Name spooler -ErrorAction SilentlyContinue
    exit 2
}

# Reiniciar el servicio de cola de impresión
try {
    Start-Service -Name spooler -ErrorAction Stop
    Write-Output "Servicio de cola de impresión iniciado."
} catch {
    Write-Output "Error al iniciar el servicio de cola de impresión: $_"
    exit 3
}
