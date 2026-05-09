# CleanMyOwn

App de limpieza y optimización para macOS construida con SwiftUI.
Inspirada en CleanMyMac pero 100 % local, sin telemetría y código abierto.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6-orange)

## Módulos

| Módulo | Qué hace |
|---|---|
| **Dashboard** | Resumen del sistema en tiempo real: disco, RAM, CPU, modelo del Mac, versión de macOS. Health Check de permisos. |
| **Limpieza** | Escanea 11 categorías de basura y permite borrarlas con selección granular. Cachés de usuario, logs, Papelera, Xcode (DerivedData / Archives / iOS DeviceSupport / Simulator caches), **cachés de devs** (npm, yarn, pnpm, pip, Homebrew, Cargo, Gradle, Maven, CocoaPods, Go, etc.), **datos huérfanos** de apps desinstaladas, **snapshots locales de Time Machine**, **simuladores iOS obsoletos**. |
| **Desinstalador** | Lista todas las apps instaladas, detecta archivos asociados (Application Support, Caches, Preferences, Containers, Saved State, HTTPStorages, WebKit, Logs, Crash Reports, LaunchAgents). **Cierra los procesos vivos antes de borrar** para evitar zombies en el Dock. |
| **Archivos grandes** | Scanner async con umbral configurable. Tab de duplicados con detección por SHA256 en 3 pasadas (size → quick hash 1 MB → full hash). Auto-selecciona duplicados manteniendo el más antiguo. |
| **Inicio** | Lista Launch Agents y Daemons. Toggle de habilitar/deshabilitar para los del usuario (renombra `.plist` ↔ `.plist.disabled` + `launchctl bootstrap/bootout`). |
| **Memoria** | Visualización en tiempo real de la presión de RAM (App / Wired / Comprimida / Caché / Libre) leyendo `vm_statistics64`. Botón "Liberar memoria" ejecuta `purge` con privilegios. |

## Permisos

- **Modo administrador** — `AdminSessionService` mantiene un `AuthorizationRef` vivo durante la sesión usando Authorization Services. Pide la contraseña UNA sola vez con `AuthorizationCreate` + `AuthorizationCopyRights`, y reutiliza la auth con `AuthorizationExecuteWithPrivileges` para todas las operaciones siguientes — **sin re-prompts**.
- **Full Disk Access** — necesario para borrar `~/Library/Containers/<bid>` (TCC bloquea el acceso incluso a `root` sin FDA). El onboarding visual al primer arranque guía al usuario a concederlo, y `PermissionsMonitor` detecta el cambio automáticamente vía polling + `NSApplication.didBecomeActiveNotification`.

## Cómo correrlo

```sh
./run.sh
```

El script compila en release con SwiftPM, empaqueta como `CleanMyOwn.app` (Info.plist + ad-hoc codesign), y lo lanza.

Requiere macOS 14+ y Xcode (sólo el toolchain de Swift, no necesitas un proyecto `.xcodeproj`).

## Estructura del proyecto

```
CleanMyOwn/
├── App/                     # @main + ContentView (sidebar + módulos)
├── Core/
│   ├── Apps/                # AppCatalogService — listar e instalar/desinstalar apps
│   ├── Cleaner/             # JunkScanService — 11 categorías de basura
│   ├── Files/               # LargeFilesService — scanner + dedup SHA256
│   ├── LaunchAgents/        # LaunchAgentService — agents/daemons
│   ├── Memory/              # MemoryService — vm_statistics64 + purge
│   ├── Permissions/         # AdminSessionService + PermissionsMonitor
│   └── SystemInfo/          # SystemInfoService — disco/RAM/CPU
├── Modules/                 # Una vista por módulo
│   ├── Dashboard/
│   ├── JunkCleaner/
│   ├── Uninstaller/
│   ├── LargeFiles/
│   ├── LoginItems/
│   └── MemoryFreer/
├── UI/
│   ├── Components/          # ProgressRing, StatCard, Sidebar
│   ├── Onboarding/          # OnboardingView (3 slides)
│   ├── Screens/             # PlaceholderView
│   └── Theme/               # Paleta + tipografía
├── Package.swift
└── run.sh
```

## Seguridad

- **Borrado permanente** (`FileManager.removeItem` / `rm -rf` con admin). Cada acción destructiva pasa por un alert de confirmación que dice explícitamente "esta acción NO se puede deshacer".
- **Detección de procesos vivos** antes de desinstalar — `terminate()` con espera 2s, luego `forceTerminate()` si hace falta. Evita locks abiertos y iconos zombie en el Dock.
- **Verificación de borrado** — después de cada operación se comprueba con `fileExists(atPath:)` que el archivo desapareció antes de removerlo de la UI. Si aún existe, se reporta como fallo (no como éxito falso).
- **Detección de huérfanos con prefix matching** — `installedBundleIDs()` usa `mdfind` + escanea `Contents/PlugIns/*.appex`, `Contents/XPCServices/*.xpc`, etc. para no marcar extensions de WhatsApp/etc. como huérfanas.

## Stack

- **SwiftUI** + **AppKit** para UI nativa
- **CryptoKit** para SHA256 de duplicados
- **Mach** APIs para CPU/memoria (`host_statistics64`, `vm_statistics64`)
- **Authorization Services** para sesión admin persistente
- **launchctl / tmutil / xcrun simctl / mdfind** para integración con macOS
