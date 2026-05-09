# CleanMyOwn

> App de limpieza, optimización y mantenimiento para macOS. SwiftUI nativo, 100 % local, sin telemetría. Inspirada en CleanMyMac.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-✓-blueviolet.svg)](https://developer.apple.com/swiftui/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](#licencia)

---

## Tabla de contenidos

- [Capturas y módulos](#capturas-y-módulos)
- [Características destacadas](#características-destacadas)
- [Instalación y ejecución](#instalación-y-ejecución)
- [Sistema de permisos](#sistema-de-permisos)
- [Cómo funciona cada módulo](#cómo-funciona-cada-módulo)
- [Decisiones de seguridad](#decisiones-de-seguridad)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Stack técnico](#stack-técnico)
- [Roadmap](#roadmap)
- [Troubleshooting](#troubleshooting)
- [Licencia](#licencia)

---

## Capturas y módulos

| Módulo | Función principal |
|---|---|
| **Dashboard** | Estado del sistema en tiempo real (Disco / RAM / CPU) + Health Check de permisos |
| **Limpieza** | Escaneo de **11 categorías** de basura con borrado granular |
| **Desinstalador** | Lista todas las apps + detección de archivos asociados + cierre de procesos vivos |
| **Archivos grandes** | Scanner async con filtro de tamaño + duplicados por SHA256 |
| **Inicio** | Gestión de Launch Agents y Daemons |
| **Memoria** | Monitor de presión de RAM + liberación con `purge` |

---

## Características destacadas

### 🧹 Limpieza con 11 categorías

| Categoría | Detección |
|---|---|
| Cachés de usuario | `~/Library/Caches/*` |
| Logs de aplicaciones | `~/Library/Logs/*` |
| Papelera | `~/.Trash/*` |
| Xcode · DerivedData | `~/Library/Developer/Xcode/DerivedData` |
| Xcode · Archives antiguos | `~/Library/Developer/Xcode/Archives` |
| Xcode · iOS DeviceSupport | `~/Library/Developer/Xcode/iOS DeviceSupport` |
| iOS Simulator · Cachés | `~/Library/Developer/CoreSimulator/Caches` |
| **Cachés de desarrollo** ⭐ | npm, yarn, pnpm, pip, Homebrew, Cargo, rustup, Gradle, Maven, CocoaPods, Composer, Go, Electron — **21 paths conocidos** |
| **Datos de apps desinstaladas** ⭐ | Detección inteligente con `mdfind` + prefix matching de bundle IDs |
| **Snapshots locales de Time Machine** ⭐ | `tmutil listlocalsnapshots /` (requiere admin) |
| **Simuladores iOS obsoletos** ⭐ | `xcrun simctl list -j` filtrando `isAvailable=false` |

### 🗑️ Desinstalador con detección de procesos vivos

Antes de borrar, se cierran TODOS los procesos asociados a la app:

1. **Match por path del executable** dentro del `.app` — agarra helpers/agents aunque el bundle ID no coincida.
2. **Match por bundle ID exacto** + sub-bundles por prefix (`com.parallels.*`).
3. **`terminate()` con espera de 2 s** → `forceTerminate()` para los rebeldes.
4. Pausa de 400 ms para que WindowServer borre los iconos zombies del Dock.

Detección de archivos asociados en 12 ubicaciones: `Application Support`, `Caches`, `Logs`, `Saved Application State`, `HTTPStorages`, `WebKit`, `Containers`, `Group Containers`, `Cookies`, `Preferences`, `LaunchAgents`, `Crash Reports`.

### 🔍 Detección de duplicados en 3 pasadas

Optimizada para no hashear todo el disco:

```
N archivos
  └─ 1) Agrupar por tamaño exacto      → descarta singles
       └─ 2) Quick hash de 1 MB        → descarta falsos por tamaño
            └─ 3) Full SHA256          → grupos confirmados
```

Resultado: < 5 % de los archivos se hashean completamente en la práctica.

### 🔓 Sesión admin persistente

A diferencia de invocar `osascript` que pide la contraseña en cada llamada, `AdminSessionService` mantiene un `AuthorizationRef` vivo dentro del proceso de la app:

```swift
AuthorizationCreate(...)          // 1 vez
AuthorizationCopyRights(...)      // pide contraseña UNA vez
// luego, durante toda la sesión:
AuthorizationExecuteWithPrivileges(...)   // sin re-prompts
```

Borrar 50 apps protegidas seguidas → **1 sola contraseña**.

### 🛡️ Onboarding de Full Disk Access

Al primer arranque, wizard de 3 pasos guía al usuario a conceder FDA. `PermissionsMonitor` detecta el cambio automáticamente (polling 2 s + `NSApplication.didBecomeActiveNotification`) y avanza solo a la pantalla "Todo listo" cuando se concede.

---

## Instalación y ejecución

### Requisitos

- macOS **14 (Sonoma)** o superior
- Xcode (sólo el toolchain de Swift, no necesitas crear `.xcodeproj`)

### Compilar y lanzar

```sh
./run.sh
```

El script:
1. Compila en modo release con `swift build -c release`.
2. Empaqueta como `CleanMyOwn.app` con `Info.plist` válido.
3. Firma ad-hoc con `codesign`.
4. Cierra cualquier instancia previa.
5. Lanza la app con `open`.

### Detener

```sh
pkill -x CleanMyOwn
```

---

## Sistema de permisos

CleanMyOwn requiere **dos permisos de macOS** para funcionar al 100 %:

### 1. Acceso completo al disco (Full Disk Access)

**Por qué:** macOS protege `~/Library/Containers/<bundle-id>` (datos de apps sandboxed) con TCC. Sin FDA, **ni siquiera `root` puede borrar esos directorios**. Es necesario para limpiar datos huérfanos de apps desinstaladas (Whisky, UTM, Parallels, etc.).

**Cómo concederlo:** el onboarding al primer arranque te lleva a `Configuración del Sistema → Privacidad y seguridad → Acceso completo al disco`. Arrastra `CleanMyOwn.app` a la lista o usa el botón **+**. La app **detecta el cambio automáticamente** sin necesidad de reiniciarla — `PermissionsMonitor` poll cada 2 s y observa `NSApplication.didBecomeActiveNotification`.

**Cómo se detecta el estado:** intentando leer `/Library/Application Support/com.apple.TCC/TCC.db`, archivo que sólo es legible con FDA concedido.

### 2. Modo administrador (Authorization Services)

**Por qué:** algunas operaciones requieren root:
- Borrar apps de `/Applications` que pertenecen a `root:wheel`.
- Borrar containers de apps sandboxed cuando hay flags de inmutabilidad.
- `tmutil deletelocalsnapshots` para snapshots de Time Machine.
- Forzar borrado de directorios protegidos.

**Cómo funciona:** se activa **bajo demanda** desde el banner del módulo. Pide contraseña una sola vez por sesión y mantiene la auth viva con `AuthorizationRef` hasta que cierras la app o pulsas "Desactivar".

---

## Cómo funciona cada módulo

### Dashboard

Lectura en tiempo real cada 2 s (`SystemInfoService.startAutoRefresh`):

- **Disco:** `URL.resourceValues(.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey)`
- **RAM:** `host_statistics64(HOST_VM_INFO64)` — calcula `active + wired + compressed` igual que Activity Monitor
- **CPU:** `host_statistics(HOST_CPU_LOAD_INFO)` — porcentaje `(user + system + nice) / total`
- **Modelo:** `sysctlbyname("hw.model", ...)`
- **macOS:** `ProcessInfo.processInfo.operatingSystemVersion`

### Limpieza

Cinco tipos de scanner despachados por `JunkScanKind`:

- **`fileBased`** — recorre `roots` con `FileManager.enumerator`, lista hijos top-level o trata el root como un solo item.
- **`devCaches`** — lista de paths conocidos para herramientas dev.
- **`orphanedAppData`** — pre-calcula `installedBundleIDs()` (vía `mdfind 'kMDItemContentType == "com.apple.application-bundle"'` + escaneo de `Contents/PlugIns/*.appex`, `Contents/XPCServices/*.xpc`, `Contents/Library/LoginItems/*.app`). Luego marca como huérfano cualquier child cuyo nombre sea un bundle ID válido **que no esté en la lista ni sea sub-bundle** (prefix matching con separador `.`).
- **`timeMachineSnapshots`** — parsea `tmutil listlocalsnapshots /`, formatea fechas a "8 may 2026 · 12:34:56".
- **`iOSSimulators`** — `xcrun simctl list -j`, filtra `isAvailable=false`, calcula tamaño de `~/Library/Developer/CoreSimulator/Devices/<UDID>/`.

Borrado despachado por `JunkItemKind`:
- `.file(URL)` → `removeItem` y, si falla y admin está activo, **fallback automático a `rm -rf` privilegiado** (cubre Containers protegidos).
- `.localSnapshot(date)` → `tmutil deletelocalsnapshots <date>` con admin.
- `.simulator(udid)` → `xcrun simctl delete <udid>`.

### Desinstalador

`AppCatalogService.scanInstalledApps()` recorre `/Applications`, `~/Applications`, `/System/Applications`, `/System/Library/CoreServices/Applications` (incluyendo subcarpetas como `Utilities/`).

Para cada `.app`:
- `Bundle(url:).infoDictionary` → name, bundleID, version
- `NSWorkspace.shared.icon(forFile:)` → ícono
- `directorySize(at:)` → tamaño en disco
- `requiresAdminToDelete(url:)` → owner=root, symlink, o padre no escribible

Búsqueda de archivos asociados (`scanAssociatedFiles`):
- Por **bundle ID** en 12 directorios estándar (`Application Support`, `Caches`, etc.)
- Por **nombre de la app** (variantes con/sin espacios) en los mismos directorios
- Plist específicos: `Preferences/<bid>.plist`, `LaunchAgents/<bid>.plist`, `Cookies/<bid>.binarycookies`

Antes de borrar, `quitRunningInstances(of:)` cierra todos los procesos relacionados.

### Archivos grandes

Scanner async (`Task.detached`) con `FileManager.enumerator` desde una raíz configurable. Filtros:
- `skipsHiddenFiles`, `skipsPackageDescendants`
- Skip de `.Trash`, symlinks
- Tratamiento especial de `.app` y packages: cuentan como UN item

Detección de duplicados con quick-hash (1 MB) + full-hash usando `CryptoKit.SHA256` y `FileHandle.read(upToCount: 4 * 1024 * 1024)`.

Auto-selección de duplicados manteniendo el más antiguo: ordena por `contentModificationDate` ascendente y selecciona todos menos el primero.

### Inicio (Launch Agents)

Enumera tres directorios:
- `~/Library/LaunchAgents` (user — toggle disponible)
- `/Library/LaunchAgents` (system — sólo lectura)
- `/Library/LaunchDaemons` (system — sólo lectura)

Para cada `.plist` parsea con `PropertyListSerialization`:
- Label, Program / ProgramArguments[0]
- RunAtLoad, KeepAlive
- Estado "cargado" comparando con `launchctl list | grep <Label>`

Toggle de user agents:
- **Deshabilitar:** `launchctl bootout gui/<UID>/<Label>` + renombrar `.plist` → `.plist.disabled`
- **Habilitar:** restaurar nombre + `launchctl bootstrap gui/<UID> <plist>`

### Memoria

Lectura cada 1.5 s de `vm_statistics64` (mismo API que Activity Monitor):

```
App Memory   = active - purgeable
Wired        = wire_count × pageSize
Comprimida   = compressor_page_count × pageSize
Caché archivos = inactive + speculative + purgeable
Libre        = free_count - speculative
```

Botón "Liberar memoria" ejecuta `/usr/sbin/purge` con privilegios admin (vía `AdminSessionService`), espera 800 ms a que el sistema reorganice, y reporta el delta de bytes.

---

## Decisiones de seguridad

| Decisión | Por qué |
|---|---|
| **Borrado permanente, NO Papelera** | El usuario lo pidió explícitamente. La operación es irreversible y cada acción destructiva pasa por un alert que dice "Esta acción NO se puede deshacer". |
| **Verificación post-borrado con `fileExists`** | Antes confiamos en el `try? removeItem`, pero podía fallar silenciosamente (typical en `/Applications` con dueño root). Ahora la app **sólo se quita de la lista en memoria si efectivamente desapareció del disco**. |
| **Cierre de procesos antes de desinstalar** | Sin esto, los iconos quedaban zombies en el Dock y los locks abiertos provocaban basura adicional. |
| **Detección de huérfanos con prefix matching** | Los falsos positivos eran extensions de apps instaladas (`net.whatsapp.WhatsApp.ServiceExtension`). Ahora si `net.whatsapp.WhatsApp` está instalado, todo `net.whatsapp.WhatsApp.X` se considera no-huérfano. |
| **Fallback automático con admin** | Containers protegidos por TCC fallan con `removeItem` aunque tengas FDA. Reintento automático con `rm -rf` privilegiado si admin está activo. |
| **`AuthorizationRef` persistente** | `osascript do shell script with administrator privileges` lanzado desde procesos independientes NO comparte cache. Mantener el ref en nuestro proceso elimina re-prompts. |

---

## Estructura del proyecto

```
CleanMyOwn/
├── App/
│   ├── CleanMyOwnApp.swift          # @main, sheet de onboarding
│   └── ContentView.swift            # layout sidebar + módulos
├── Core/
│   ├── Apps/
│   │   └── AppCatalogService.swift  # scan apps + uninstall + kill processes
│   ├── Cleaner/
│   │   └── JunkScanService.swift    # 11 scanners + dispatch de borrado
│   ├── Files/
│   │   └── LargeFilesService.swift  # scan + dedup SHA256
│   ├── LaunchAgents/
│   │   └── LaunchAgentService.swift # parse plists + toggle
│   ├── Memory/
│   │   └── MemoryService.swift      # vm_statistics64 + purge
│   ├── Permissions/
│   │   ├── AdminSessionService.swift   # AuthorizationRef + AEWP
│   │   └── PermissionsMonitor.swift    # FDA en vivo + observer
│   └── SystemInfo/
│       └── SystemInfoService.swift  # disco/RAM/CPU/modelo
├── Modules/
│   ├── Dashboard/DashboardView.swift
│   ├── JunkCleaner/JunkCleanerView.swift
│   ├── Uninstaller/UninstallerView.swift
│   ├── LargeFiles/LargeFilesView.swift
│   ├── LoginItems/LoginItemsView.swift
│   └── MemoryFreer/MemoryFreerView.swift
├── UI/
│   ├── Components/
│   │   ├── ProgressRing.swift
│   │   ├── Sidebar.swift
│   │   └── StatCard.swift
│   ├── Onboarding/
│   │   └── OnboardingView.swift     # wizard 3 slides
│   ├── Screens/
│   │   └── PlaceholderView.swift
│   └── Theme/
│       └── Theme.swift              # paleta + tipografía
├── Package.swift                    # SwiftPM executable target
├── run.sh                           # build + package + launch
└── README.md
```

---

## Stack técnico

| Tecnología | Uso |
|---|---|
| **SwiftUI** | UI declarativa nativa con `@StateObject`, `@EnvironmentObject` |
| **AppKit** | `NSWorkspace`, `NSRunningApplication`, `NSImage`, `NSOpenPanel` |
| **CryptoKit** | `SHA256` streaming para hash de duplicados |
| **Foundation** | `FileManager`, `Process`, `PropertyListSerialization`, `URLResourceValues` |
| **Mach** | `host_statistics64`, `vm_statistics64`, `host_cpu_load_info` |
| **Security** | `Authorization Services` para sesión admin persistente |
| **Combine** | `@Published` properties en `ObservableObject` services |
| **CLI integrations** | `launchctl`, `tmutil`, `xcrun simctl`, `mdfind`, `osascript` |

---

## Roadmap

### Próximas mejoras de alto impacto

- [ ] **Helper privilegiado con SMAppService** — admin persistido entre sesiones, sin reactivar cada vez.
- [ ] **Análisis del disco estilo DaisyDisk** — sunburst chart navegable de qué carpetas comen más espacio.
- [ ] **Ranking "rara vez usado"** — usar `kMDItemLastUsedDate` para sugerir archivos grandes que no abres hace meses.
- [ ] **Detección de archivos en uso** (`lsof`) antes de borrar — evita corromper datos de procesos vivos.
- [ ] **Paralelización del escaneo** — `TaskGroup` para escanear las 11 categorías a la vez.
- [ ] **App firmada con Developer ID + notarizada** — aparece con icono y nombre bonito en lista FDA en vez de path raro.

### UX

- [ ] Notificaciones cuando se libera espacio significativo
- [ ] Menubar item para acceso rápido a "Liberar memoria"
- [ ] Whitelist de paths que el usuario nunca quiere tocar
- [ ] Modo "borrado a Papelera" como opción (toggle)

---

## Troubleshooting

### "Falta Acceso completo al disco" no desaparece después de concederlo

`PermissionsMonitor` re-checa al volver al foreground y cada 2 s mientras estés en una pantalla que necesite FDA. Si no se actualiza:
1. Pulsá el botón refresh ↻ del banner.
2. Cerrá y reabrí la app — los permisos TCC se aplican al iniciar el proceso.

### "El modo administrador sigue pidiendo contraseña"

Confirmá que el modo está realmente **activo** (banner verde con "Modo administrador activo"). Si lo desactivaste o la sesión expiró, el siguiente borrado pedirá password de nuevo.

### Algunos archivos siguen sin borrarse aún con admin + FDA

Tienen flags de inmutabilidad (`uchg`/`schg`). Solución: con admin activo, ejecutá manualmente:
```sh
sudo chflags -R noschg /path/protegido && sudo rm -rf /path/protegido
```

### La app no aparece con icono bonito en la lista FDA

Es ad-hoc signed (sin Developer ID). macOS la lista por path. Si **mueves o recompilas** la app, el path cambia y FDA queda inválido — hay que volver a añadirla. Solución definitiva: `./run.sh` siempre desde la misma ubicación, o firmar con Developer ID.

---

## Licencia

MIT.

---

Hecho con SwiftUI y dedicación al detalle. PRs y feedback bienvenidos.
