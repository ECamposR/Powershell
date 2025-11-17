# Colección de Scripts de PowerShell para Administración y Diagnóstico de Windows

Este repositorio contiene una colección de scripts de PowerShell diseñados para realizar tareas de diagnóstico y administración en sistemas operativos Windows.

## Descripción de los Scripts

A continuación se detalla la función de cada script:

### `analisis_rendimiento.ps1`

Este es un script de diagnóstico de rendimiento avanzado que recopila una amplia gama de métricas del sistema para ayudar a identificar problemas de rendimiento.

**Funcionalidades:**
- Muestra información general del sistema (SO, arquitectura, tiempo de actividad).
- Informa sobre el uso actual de la CPU y la memoria RAM.
- Detalla el espacio utilizado y libre en todos los discos.
- Mide el rendimiento de I/O de los discos físicos.
- Muestra el uso del archivo de paginación.
- Lista los 5 procesos que más CPU y RAM consumen.
- Muestra los errores y eventos críticos recientes de los registros de Sistema y Aplicación.
- Enumera los programas que se ejecutan al inicio.
- Comprueba el estado de salud S.M.A.R.T. de los discos físicos.

**Uso:**
```powershell
.\analisis_rendimiento.ps1
```
Se recomienda ejecutar como Administrador para obtener toda la información.

### `clic_to_run_office.ps1`

Este script gestiona las actualizaciones de las instalaciones de Microsoft Office del tipo "Click-to-Run".

**Funcionalidades:**
- Detecta si Office está instalado como "Click-to-Run".
- Determina el canal de actualización configurado (Current, Monthly, etc.).
- Inicia el proceso de actualización de Office.
- Permite configurar si se muestra la interfaz de actualización y si se fuerza el cierre de aplicaciones.

**Uso:**
El script parece estar diseñado para ser usado con parámetros que se le pasan desde otra herramienta, pero puede ser ejecutado directamente.
```powershell
.\clic_to_run_office.ps1
```

### `erroreshw.ps1`

Busca específicamente eventos de `Microsoft-Windows-WHEA-Logger` en el registro del sistema. La presencia de estos eventos es un fuerte indicador de problemas de hardware.

**Funcionalidades:**
- Filtra y muestra los eventos de WHEA-Logger.
- Alerta al usuario si se encuentran este tipo de eventos.

**Uso:**
```powershell
.\erroreshw.ps1
```
Es crucial ejecutarlo como Administrador.

### `eventosprevioreinicios.ps1`

Ayuda a diagnosticar la causa de reinicios inesperados analizando los eventos que ocurrieron justo antes de un reinicio.

**Funcionalidades:**
- Requiere la fecha y hora del reinicio como parámetro.
- Busca eventos de tipo Crítico, Error y Advertencia en los registros de Sistema y Aplicación en los minutos previos a la hora especificada.

**Uso:**
```powershell
.\eventosprevioreinicios.ps1 -HoraReinicio "AAAA-MM-DD HH:MM:SS" -MinutosAntes 30
```

### `Get-SysmonConnection.ps1`

Contiene una función de PowerShell que utiliza los datos de Sysmon (System Monitor) para encontrar qué procesos han realizado conexiones de red hacia una dirección IP específica.

**Funcionalidades:**
- Define la función `Get-SysmonConnection`.
- Busca en los eventos de Sysmon (ID 3: Conexión de red) el destino IP especificado.
- Devuelve un objeto con detalles de la conexión: proceso, usuario, puerto, etc.

**Uso:**
Primero se debe cargar la función y luego llamarla:
```powershell
. .\Get-SysmonConnection.ps1
Get-SysmonConnection -DestinationIP "1.1.1.1"
```

### `hardware.ps1`

Recopila y muestra un resumen detallado del hardware y software del sistema.

**Funcionalidades:**
- Información del procesador, memoria RAM, almacenamiento.
- Detalles de la placa base, BIOS y GPU.
- Número de serie del equipo (Service Tag) y UUID.
- Versión del sistema operativo y fecha de instalación.

**Uso:**
```powershell
.\hardware.ps1
```

### `listardrivers.ps1`

Lista todos los controladores de dispositivos instalados que no son de Microsoft. Es útil para identificar drivers de terceros que puedan causar inestabilidad o conflictos.

**Funcionalidades:**
- Busca en `Win32_PnPSignedDriver` los drivers cuyo fabricante no es "Microsoft".
- Muestra el nombre del dispositivo, fabricante, versión y fecha del controlador.
- Proporciona un método alternativo usando `Get-WindowsDriver`.

**Uso:**
```powershell
.\listardrivers.ps1
```
Se recomienda ejecutar como Administrador.

### `reinicios.ps1`

Un script de diagnóstico integral diseñado específicamente para investigar las causas de reinicios inesperados del sistema. Combina la funcionalidad de varios de los otros scripts en uno solo.

**Funcionalidades:**
- Recopila información del sistema y hardware.
- Busca eventos críticos de reinicio (IDs 6008, 1001, 41).
- Busca errores de hardware (WHEA-Logger).
- Verifica la configuración y existencia de archivos de volcado de memoria (Minidumps).
- Comprueba el estado de salud (SMART) de los discos.
- Lista los drivers de terceros y las actualizaciones de Windows recientes.
- Proporciona un resumen de hallazgos y recomendaciones.

**Uso:**
```powershell
.\reinicios.ps1
```
**Se debe ejecutar como Administrador** para que sea efectivo.

### `reset_wupdate.ps1`

Este script intenta solucionar problemas con el Agente de Windows Update reseteando sus componentes.

**Funcionalidades:**
- Detiene los servicios de Windows Update, Criptografía, BITS e Instalador de Windows.
- Renombra las carpetas `SoftwareDistribution` y `catroot2` a `.old`.
- Reinicia los servicios detenidos.

**Uso:**
```powershell
.\reset_wupdate.ps1
```
Es necesario ejecutarlo como Administrador. Se recomienda reiniciar el equipo después de ejecutarlo.

```