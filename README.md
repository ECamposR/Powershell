# Colección de Scripts de PowerShell para Administración y Diagnóstico de Windows

Este repositorio contiene una colección de scripts de PowerShell diseñados para realizar tareas de diagnóstico y administración en sistemas operativos Windows.

## Tabla de Contenido

| Categoría | Scripts |
| --- | --- |
| Diagnóstico y monitoreo | [analisis_rendimiento.ps1](#analisis_rendimientops1), [diagnostico_bloqueos.ps1](#diagnostico_bloqueosps1), [eventosprevioreinicios.ps1](#eventosprevioreiniciosps1), [erroreshw.ps1](#erroreshwps1), [Get-SysmonConnection.ps1](#get-sysmonconnectionps1), [log_display.ps1](#log_displayps1), [logs_camara.ps1](#logs_camaraps1), [monitor_tdr.ps1](#monitor_tdrps1), [reinicios.ps1](#reiniciosps1) |
| Redes y conectividad | [cambiar-dns.ps1](#cambiar-dnsps1), [cambio-hosts.ps1](#cambio-hostsps1), [ControlHotspot.ps1](#controlhotspotps1), [ps-mtr.ps1](#ps-mtrps1), [Sync-Time.ps1](#sync-timeps1) |
| Hardware e inventario | [hardware.ps1](#hardwareps1), [hardware2.ps1](#hardware2ps1), [listardrivers.ps1](#listardriversps1) |
| Mantenimiento y actualizaciones | [clic_to_run_office.ps1](#clic_to_run_officeps1), [limpieza_disco.ps1](#limpieza_discops1), [reset_wupdate.ps1](#reset_wupdateps1) |
| Impresión y periféricos | [borrar_cola_impresion.ps1](#borrar_cola_impresionps1), [fix_cam_now.ps1](#fix_cam_nowps1), [fix_cam_now.cmd](#fix_cam_nowcmd), [impresora-ip.ps1](#impresora-ipps1) |
| Active Directory y respaldos | [Export-ADConfig_AD.ps1](#export-adconfig_adps1), [Retention-Pairs.ps1](#retention-pairsps1) |

## Descripción de los Scripts

### Diagnóstico y monitoreo

#### analisis_rendimiento.ps1

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

#### diagnostico_bloqueos.ps1

Recopila evidencia detallada ante bloqueos o pantallazos negros, generando logs y reportes empaquetados.

**Funcionalidades:**
- Auto-verifica que se ejecute como Administrador y centraliza la salida en `$PSScriptRoot` mediante `Start-Transcript`.
- Extrae eventos relevantes (Kernel-Power, WHEA, Display, LiveKernelEvent, VSS, NTFS, UrBackup/Sophos/DriveFS) y estado de servicios o instalaciones relacionados.
- Ejecuta diagnósticos de disco y memoria (`Get-PhysicalDisk`, `Get-StorageReliabilityCounter`, `fsutil dirty query`, `Win32_PageFileUsage`, drivers de video, volcados en `LiveKernelReports`).
- Lanza `sfc`, `dism`, `powercfg /energy`, `powercfg /batteryreport` y `vssadmin`, guardando artefactos en la carpeta del script.
- Opcionalmente detiene UrBackup/GoogleDriveFS, habilita `CrashOnCtrlScroll` y empaqueta todo en un ZIP con timestamp.

**Uso:**
```powershell
.\diagnostico_bloqueos.ps1 [-SinceDays 7] [-EnergyDurationSeconds 60] [-TryStopUrBackup] [-TryStopGoogleDriveFS] [-EnableCrashOnCtrlScroll]
```
Produce un `.log` y ZIP en la carpeta del script.

#### eventosprevioreinicios.ps1

Ayuda a diagnosticar la causa de reinicios inesperados analizando los eventos que ocurrieron justo antes de un reinicio.

**Funcionalidades:**
- Requiere la fecha y hora del reinicio como parámetro.
- Busca eventos de tipo Crítico, Error y Advertencia en los registros de Sistema y Aplicación en los minutos previos a la hora especificada.

**Uso:**
```powershell
.\eventosprevioreinicios.ps1 -HoraReinicio "AAAA-MM-DD HH:MM:SS" -MinutosAntes 30
```

#### erroreshw.ps1

Busca específicamente eventos de `Microsoft-Windows-WHEA-Logger` en el registro del sistema. La presencia de estos eventos es un fuerte indicador de problemas de hardware.

**Funcionalidades:**
- Filtra y muestra los eventos de WHEA-Logger.
- Alerta al usuario si se encuentran este tipo de eventos.

**Uso:**
```powershell
.\erroreshw.ps1
```
Es crucial ejecutarlo como Administrador.

#### Get-SysmonConnection.ps1

Contiene una función que interroga los eventos de Sysmon (ID 3) para saber qué procesos realizaron conexiones hacia una IP específica.

**Funcionalidades:**
- Agrega la función `Get-SysmonConnection` al entorno actual.
- Busca en los eventos de Sysmon usando la IP de destino y entrega proceso, usuario, puertos y otros metadatos.
- Facilita la trazabilidad forense de conexiones sin depender de herramientas externas.

**Uso:**
```powershell
. .\Get-SysmonConnection.ps1
Get-SysmonConnection -DestinationIP "1.1.1.1"
```

#### log_display.ps1

Monitoriza en tiempo real eventos de drivers de video y guarda un registro continuo.

**Funcionalidades:**
- Determina la carpeta donde se ejecuta y escribe en `monitor_display_log.txt`.
- Cada 3 segundos consulta el log de Sistema y filtra eventos de proveedores `Display`, `dxgkrnl`, `nvlddmkm`, `amdkmdag`, `igfx`, etc.
- Registra fecha ISO, EventID, proveedor y mensaje plano para facilitar correlación con cuelgues/TDR.

**Uso:**
```powershell
.\log_display.ps1
```
Detén el script con `Ctrl+C` cuando ya no necesites capturar eventos.

#### logs_camara.ps1

Recolecta todo lo necesario para diagnosticar problemas de cámara en un solo archivo de texto bajo `C:\`.

**Funcionalidades:**
- Genera `C:\logs_yyyyMMdd_HHmmss.txt` y vuelca eventos de Application/System (hasta 10000) y canales específicos de drivers/PnP.
- Incluye información WMI de dispositivos de imagen, salida completa de `dxdiag` y tabla de controladores (`Get-PnpDevice`).
- Usa funciones defensivas que comprueban si cada canal de eventos es accesible antes de intentar leerlo.

**Uso:**
```powershell
.\logs_camara.ps1
```
Ejecutar como Administrador para acceder a todos los registros.

#### monitor_tdr.ps1

Genera un monitor persistente para TDR/LiveKernelEvent que guarda estado entre ejecuciones.

**Funcionalidades:**
- Define un script embebido y lo guarda como `C:\Tools\monitor_tdr.ps1`, creando la carpeta si no existe.
- El script generado rastrea eventos `Display` y `Windows Error Reporting` desde el último timestamp guardado en `tdr_state.json`.
- Registra cada incidencia en `tdr_events.csv` con hora, origen, Id y resumen para análisis posterior.

**Uso:**
```powershell
.\monitor_tdr.ps1
```
Tras ejecutarlo, programa `C:\Tools\monitor_tdr.ps1` (Task Scheduler) para que recopile eventos continuamente.

#### reinicios.ps1

Script integral para investigar las causas de reinicios inesperados, combinando varias de las comprobaciones anteriores.

**Funcionalidades:**
- Recopila información del sistema y hardware.
- Busca eventos críticos de reinicio (IDs 6008, 1001, 41) y errores de hardware (WHEA-Logger).
- Verifica minidumps configurados, estado SMART, drivers de terceros y actualizaciones de Windows recientes.
- Presenta un resumen de hallazgos y recomendaciones.

**Uso:**
```powershell
.\reinicios.ps1
```
Se debe ejecutar como Administrador para que sea efectivo.

### Redes y conectividad

#### cambiar-dns.ps1

Asistente interactivo para cambiar los DNS de una interfaz activa entre Cloudflare (1.1.1.1) y el DNS corporativo.

**Funcionalidades:**
- Comprueba privilegios administrativos; si no existen, solicita credenciales y se relanza con `Start-Process -Credential`.
- Permite elegir el perfil de DNS deseado y enumerar las interfaces IPv4 que estén en estado `Up`.
- Aplica los cambios con `Set-DnsClientServerAddress` y muestra la configuración resultante.

**Uso:**
```powershell
.\cambiar-dns.ps1
```
Puede usarse `-SkipElevation` si ya se ejecuta como Administrador.

#### cambio-hosts.ps1

Asegura que el archivo `hosts` local incluya la entrada para `Servidor5` apuntando a `192.168.2.2`.

**Funcionalidades:**
- Verifica ejecución como Administrador y crea un respaldo del archivo `hosts` la primera vez.
- Comprueba si existe la entrada objetivo antes de escribir para evitar duplicados.
- Permite ajustar fácilmente la IP o alias dentro del arreglo `$entries`.

**Uso:**
```powershell
.\cambio-hosts.ps1
```
Ejecutar en cada equipo que necesite el parche temporal.

#### ControlHotspot.ps1

Bloquea o restaura el uso de Mobile Hotspot/ICS en Windows combinando cambios en servicios y políticas de registro.

**Funcionalidades:**
- Auto-elevación a Administrador si el script no se inicia con permisos elevados.
- Detecta si los servicios `icssvc` (Mobile Hotspot) y `SharedAccess` (ICS) están deshabilitados y sugiere la acción opuesta (bloquear o habilitar).
- En modo **BLOQUEAR** detiene ambos servicios, los configura como `Disabled` y aplica la directiva `NC_ShowSharedAccessUI = 1`.
- En modo **DESBLOQUEAR** restaura los servicios a inicio `Manual` y elimina la clave de registro para devolver la funcionalidad predeterminada.
- Todo cambio requiere confirmación escribiendo `S` y reporta posibles conflictos con GPO.

**Uso:**
```powershell
.\ControlHotspot.ps1
```
Se recomienda ejecutar como Administrador (el script intentará auto-elevarse si es necesario).

#### ps-mtr.ps1

Implementación en PowerShell de un `mtr` simplificado que mide latencia y pérdida por hop.

**Funcionalidades:**
- Usa `tracert` una sola vez para descubrir los saltos hacia el destino indicado.
- Realiza `Test-Connection` cíclicos a cada hop, calculando `Loss%`, `Last`, `Avg`, `Best` y `Worst` en una ventana móvil.
- Opciones para limitar hops, ajustar intervalos/timeout y deshabilitar resolución DNS (`-NoDNS`).
- Refresca la consola en vivo hasta que se cancele con `Ctrl+C`.

**Uso:**
```powershell
.\ps-mtr.ps1 -Target ejemplo.com [-MaxHops 30] [-IntervalMs 1000] [-TimeoutMs 800] [-NoDNS]
```

#### Sync-Time.ps1

Sincroniza hora y zona horaria en equipos fuera de dominio y deja trazabilidad en `C:\Windows\Temp\TimeSync.log`.

**Funcionalidades:**
- Ajusta la zona horaria a `Central America Standard Time` (modificable) comparando con el estado actual (`tzutil /g`).
- Espera hasta 2 minutos a tener conectividad ICMP (1.1.1.1 / 8.8.8.8) antes de continuar.
- Configura el servicio `W32Time`, define peers NTP (`time.windows.com`, `time.google.com`, `pool.ntp.org`), reinicia el servicio y lanza reintentos de `w32tm /resync`.
- Registra el resultado de cada paso, incluyendo `w32tm /query /status` y `/peers`.

**Uso:**
```powershell
.\Sync-Time.ps1
```
Debe ejecutarse como Administrador (`#requires -RunAsAdministrator`).

### Hardware e inventario

#### hardware.ps1

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

#### hardware2.ps1

Inventario detallado de almacenamiento y memoria RAM pensado para ejecutarse incluso en sesiones PowerShell de 32 bits.

**Funcionalidades:**
- Si detecta proceso PowerShell de 32 bits en un SO de 64 bits se relanza automáticamente usando `SysNative`.
- Usa CIM/WMI, `Get-Disk`, `Get-PhysicalDisk` y `wmic` para consolidar modelo, serie, bus, firmware, capacidad y estado de cada disco.
- Mapea módulos RAM con capacidad, velocidad configurada, tipo (DDR), factor de forma, voltaje y calcula resumen de slots/máxima capacidad soportada.
- Formatea todo en tablas ASCII (`Print-Table`) fáciles de pegar en informes o tickets.

**Uso:**
```powershell
.\hardware2.ps1
```

#### listardrivers.ps1

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

### Mantenimiento y actualizaciones

#### clic_to_run_office.ps1

Gestiona las actualizaciones de instalaciones de Microsoft Office del tipo "Click-to-Run".

**Funcionalidades:**
- Detecta si Office está instalado como "Click-to-Run".
- Determina el canal de actualización configurado (Current, Monthly, etc.).
- Inicia el proceso de actualización de Office.
- Permite configurar si se muestra la interfaz de actualización y si se fuerza el cierre de aplicaciones.

**Uso:**
```powershell
.\clic_to_run_office.ps1
```
El guion puede recibir parámetros desde herramientas externas, pero también puede ejecutarse directamente.

#### limpieza_disco.ps1

Menú interactivo para liberar espacio en disco combinando tareas comunes de mantenimiento, con un reporte final detallado.

**Funcionalidades:**
- **Reporte Dual:** Al finalizar, distingue entre "Espacio liberado" (archivos borrados explícitamente) y "Impacto real en Disco C:" (ganancia neta de espacio libre), capturando limpiezas complejas como WinSxS.
- **Medición Precisa:** Calcula el tamaño de la Papelera de Reciclaje y los logs de eventos antes de eliminarlos para un reporte exacto.
- **Limpieza Integral:** Borra temporales, caché de Windows Update, vacía la papelera, ejecuta `dism ... /startcomponentcleanup` (WinSxS) y purga logs de eventos/CBS/DISM.
- **Interactivo:** Permite ejecutar acciones individuales o todas a la vez.

**Uso:**
```powershell
.\limpieza_disco.ps1
```
Interactivo; selecciona opciones `1-6` o `Q` para salir y ver el informe.

#### reset_wupdate.ps1

Intenta solucionar problemas con el agente de Windows Update reseteando sus componentes.

**Funcionalidades:**
- Detiene los servicios de Windows Update, Criptografía, BITS e Instalador de Windows.
- Renombra las carpetas `SoftwareDistribution` y `catroot2` a `.old`.
- Reinicia los servicios detenidos.

**Uso:**
```powershell
.\reset_wupdate.ps1
```
Es necesario ejecutarlo como Administrador y se recomienda reiniciar después.

### Impresión y periféricos

#### borrar_cola_impresion.ps1

Limpia por completo la cola de impresión de Windows deteniendo temporalmente el servicio `spooler`.

**Funcionalidades:**
- Detiene el servicio de cola de impresión (`spooler`) de forma forzada para evitar archivos bloqueados.
- Elimina todos los trabajos pendientes del directorio `%windir%\System32\spool\PRINTERS`.
- Reinicia el servicio al finalizar y reporta errores en cada fase.

**Uso:**
```powershell
.\borrar_cola_impresion.ps1
```
Requiere consola con privilegios elevados.

#### fix_cam_now.ps1

Reinicia la canalización de video para cámaras UVC sin reiniciar el sistema, dejando evidencia en un log.

**Funcionalidades:**
- Se auto-eleva vía UAC y crea un transcript con nombre `fix_cam_now_YYYYMMDD_HHMMSS.log` junto al script.
- Antes de aplicar cambios, recopila drivers de cámara y eventos recientes (WER 141/TDR, Display, Kernel-PnP).
- Reinicia servicios (`FrameServer`, `stisvc`, `camsvc`), cierra aplicaciones comunes que retienen la cámara y deshabilita/habilita cada dispositivo vía `pnputil`.
- Ofrece modo silencioso (`-Silent`) para saltar cuadros de diálogo y `-WindowMinutes` para ajustar la ventana de eventos.

**Uso:**
```powershell
.\fix_cam_now.ps1 [-WindowMinutes 120] [-Silent]
```

#### fix_cam_now.cmd

Wrapper en batch para lanzar `fix_cam_now.ps1` desde Mesh Agent con doble clic.

**Funcionalidades:**
- Comprueba que `C:\Program Files\Mesh Agent\fix_cam_now.ps1` exista antes de ejecutar.
- Invoca PowerShell con `-ExecutionPolicy Bypass` y el parámetro `-Silent`.
- Muestra mensajes de éxito/error y deja la ventana abierta con `pause` para asistir al técnico.

**Uso:**
```cmd
fix_cam_now.cmd
```
Ejecutar desde el explorador o consola con permisos administrativos.

#### impresora-ip.ps1

Crea una impresora local apuntando directamente a la Canon iR-ADV C359 en 192.168.2.14 reutilizando el driver instalado.

**Funcionalidades:**
- Valida privilegios de administrador, busca el driver definido por `$driverPattern` y se detiene si no se encuentra.
- Genera (o reutiliza) el puerto TCP/IP `IP_192.168.2.14`.
- Añade la impresora `iR-ADV C359 IP` conectada a dicho puerto usando `Add-Printer`.

**Uso:**
```powershell
.\impresora-ip.ps1
```
Modifica `$printerIP`/`$driverPattern` si la infraestructura cambia.

### Active Directory y respaldos

#### Export-ADConfig_AD.ps1

Documenta una infraestructura de Active Directory exportando configuración de bosque, dominio, DCs y OUs.

**Funcionalidades:**
- Carga el módulo `ActiveDirectory`, obtiene contexto del dominio/forest y crea una carpeta con timestamp en `C:\AD_Documentacion` (personalizable).
- Genera `AD_ReporteGeneral.txt` con datos del bosque, dominio y controladores (sitio, OS, GC, etc.).
- Crea `AD_OUs.txt` con el listado completo de unidades organizativas e indicador de protección contra eliminación accidental.
- Opcionalmente incluye un tercer archivo `AD_OU_ACL.txt` con las ACL de cada OU al usar `-IncludeOUAcl`.

**Uso:**
```powershell
.\Export-ADConfig_AD.ps1 [-OutputRoot C:\AD_Documentacion] [-IncludeOUAcl]
```
Debe ejecutarse en un equipo con RSAT/AD DS Tools y permisos adecuados.

#### Retention-Pairs.ps1

Aplica una política de retención por pares para backups `.sql` + `.zip` nombrados con timestamp `YYYYMMDDhhmmss`.

**Funcionalidades:**
- Escanea el directorio indicado, agrupa archivos válidos por “clave” y detecta pares completos/incompletos.
- Mantiene al menos `-MinPairsToKeep` pares completos (5 por defecto) y marca para eliminación los más antiguos cuando hay excedente.
- Soporta modo simulación (`-DryRun`) y genera un log detallado (por defecto `Retention-YYYYMMDD.log` en la misma carpeta).
- Controla códigos de salida distintos para errores de permisos, I/O o inconsistencias.

**Uso:**
```powershell
.\Retention-Pairs.ps1 -BackupPath "D:\Backups\DB" [-MinPairsToKeep 5] [-DryRun] [-LogPath C:\Logs\retencion.log]
```
