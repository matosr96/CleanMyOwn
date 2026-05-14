# CleanMyOwn

> **A native macOS cleaner and maintenance app.** SwiftUI, 100% local, no telemetry, no helper daemons. Inspired by CleanMyMac.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-✓-blueviolet.svg)](https://developer.apple.com/swiftui/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](#license)

CleanMyOwn is a SwiftUI desktop app that scans, cleans, and maintains a macOS system end to end: junk caches, orphaned app data, large files and duplicates, uninstalling apps with their leftovers, login items, and live memory pressure. It talks directly to Mach (`host_statistics64`, `vm_statistics64`), TCC, and Authorization Services — no scripted wrappers, no Electron, no background helper.

---

## Why

Most macOS cleaners fall into one of three traps: they ship a privileged helper that ages badly, they shell out to `osascript` and trigger a password prompt for every action, or they delete blindly and leave the Dock full of zombie icons. CleanMyOwn was built to skip all three.

The interesting problems in this domain aren't UI — they're **state**: which bundle IDs are actually still installed, which processes hold a `.app` open, which files are protected by TCC even from root, which auth session is still valid. Most of the engineering work here is about answering those questions correctly and cheaply.

---

## Highlights

- **11-category junk scanner** including dev caches (npm, pnpm, pip, Homebrew, Cargo, Gradle, Maven, CocoaPods, Composer, Go, Electron — 21 known paths), iOS Simulator caches, Time Machine local snapshots, and obsolete simulators.
- **Smart orphan detection** for sandboxed app data using `mdfind` + prefix-matching on bundle IDs — no false positives on installed sub-bundles like `net.whatsapp.WhatsApp.ServiceExtension`.
- **Uninstaller that closes live processes first** via dual path/bundle-ID match, then `terminate()` with 2s grace, then `forceTerminate()`. Detects associated files across 12 standard locations.
- **3-pass duplicate detection** (size bucket → 1MB quick hash → full SHA-256 streaming). Less than 5% of scanned files end up fully hashed in practice.
- **Persistent admin session** via long-lived `AuthorizationRef` — one password prompt per app launch, not per action. Deleting 50 protected apps in a row = 1 prompt.
- **Live Full Disk Access detection** via TCC.db readability probe + 2s polling + `NSApplication.didBecomeActiveNotification` — no app restart required after granting.
- **Memory monitor that matches Activity Monitor** by calling `vm_statistics64` directly with the same `active + wired + compressed` formula.
- **Native end to end:** SwiftUI + AppKit, no Electron, no background daemon, no telemetry.

---

## Tech stack

| Layer | Choice |
|---|---|
| UI | SwiftUI (`@StateObject`, `@EnvironmentObject`, custom modifiers) |
| System integration | AppKit (`NSWorkspace`, `NSRunningApplication`), Mach syscalls (`host_statistics64`, `vm_statistics64`) |
| Privileged operations | Authorization Services (`AuthorizationCreate` + `AuthorizationExecuteWithPrivileges`) |
| Hashing | CryptoKit `SHA256` streaming, 4MB chunks |
| Concurrency | `Task.detached`, `@Published` over Combine |
| CLI bridges | `launchctl`, `tmutil`, `xcrun simctl`, `mdfind`, `osascript` |
| Build | SwiftPM executable target, ad-hoc codesign, `run.sh` packager |

---

## Architecture

```
CleanMyOwn/
├── App/
│   ├── CleanMyOwnApp.swift          # @main, onboarding sheet wiring
│   └── ContentView.swift            # sidebar + cross-faded module host
├── Core/
│   ├── Apps/AppCatalogService.swift     # app scan, process kill, uninstall
│   ├── Cleaner/JunkScanService.swift    # 5 scanner kinds, 11 categories
│   ├── Files/LargeFilesService.swift    # async enumerator + dedup pipeline
│   ├── LaunchAgents/LaunchAgentService.swift  # plist parsing, bootout/bootstrap
│   ├── Memory/MemoryService.swift       # vm_statistics64 + purge orchestration
│   ├── Permissions/
│   │   ├── AdminSessionService.swift    # long-lived AuthorizationRef + AEWP
│   │   └── PermissionsMonitor.swift     # FDA probe via TCC.db readability
│   └── SystemInfo/SystemInfoService.swift  # disk/RAM/CPU/model polling
├── Modules/                          # one folder per feature view
│   ├── Dashboard/  JunkCleaner/  Uninstaller/
│   ├── LargeFiles/ LoginItems/   MemoryFreer/
├── UI/
│   ├── Components/                   # ProgressRing, Confetti, Shimmer, …
│   ├── Onboarding/OnboardingView.swift  # 3-step FDA wizard
│   └── Theme/                        # palette, typography, animations
├── Package.swift                     # SwiftPM executable
└── run.sh                            # build → bundle → codesign → launch
```

---

## Engineering decisions worth a look

A handful of choices that aren't obvious from the file tree:

**Persistent `AuthorizationRef` instead of per-call `osascript`.** Each `osascript do shell script with administrator privileges` invocation runs in its own process and does not share the auth cache, so a 50-app batch uninstall would prompt 50 times. The app holds a single `AuthorizationRef` inside its own process, calls `AuthorizationCopyRights` once, and then routes every privileged shell command through `AuthorizationExecuteWithPrivileges`. One password prompt per session. See [AdminSessionService.swift](Core/Permissions/AdminSessionService.swift).

**FDA status probed via TCC.db, not entitlement APIs.** macOS does not expose a public API to ask "do I have Full Disk Access?" The reliable proxy is whether `/Library/Application Support/com.apple.TCC/TCC.db` is readable — it requires FDA to open. `PermissionsMonitor` does that probe on a 2-second timer and on `NSApplication.didBecomeActiveNotification`, so the UI updates the instant the user grants permission in System Settings without an app restart. See [PermissionsMonitor.swift](Core/Permissions/PermissionsMonitor.swift).

**Orphan detection with prefix matching on bundle IDs.** The naïve version — "delete `~/Library/Containers/<bid>` if no app with that bundle ID is installed" — flags real sub-bundles like `net.whatsapp.WhatsApp.ServiceExtension` as orphans. The scanner pre-computes the set of installed bundle IDs via `mdfind`, then walks each app bundle for `Contents/PlugIns/*.appex`, `XPCServices/*.xpc`, and `LoginItems/*.app`. A candidate is an orphan only if no installed ID is a `.`-separated prefix of it. See [JunkScanService.swift](Core/Cleaner/JunkScanService.swift).

**3-pass duplicate pipeline.** Hashing every large file is wasteful — most files have unique sizes. The pipeline groups by exact size, drops singletons, hashes only the first 1 MB to drop accidental size matches, and only then runs full SHA-256 streamed in 4 MB chunks. Empirically <5% of candidates reach the third pass. See [LargeFilesService.swift](Core/Files/LargeFilesService.swift).

**Automatic privileged fallback on delete failures.** `FileManager.removeItem` can fail silently on sandboxed Containers even with FDA granted, because TCC owns them with flags `removeItem` won't override. When admin mode is active, a failed delete retries as a privileged `rm -rf` through the persistent `AuthorizationRef`. After every delete the app re-checks `FileManager.fileExists(atPath:)` and only updates the in-memory list when the path actually disappeared — so the UI never lies about disk state.

**Process termination before uninstall.** Deleting an open `.app` leaves zombie Dock icons and locked handles. The uninstaller matches running processes two ways: by executable path inside the bundle (catches helpers whose bundle ID does not match the parent app) and by exact bundle ID plus prefix sub-bundles. It calls `terminate()` first, waits 2 seconds, then `forceTerminate()` on holdouts, then sleeps 400 ms for WindowServer to clear icons before the delete. See [AppCatalogService.swift](Core/Apps/AppCatalogService.swift).

**Memory readings via direct Mach syscalls.** `MemoryService` calls `host_statistics64(HOST_VM_INFO64, …)` and applies the same `active + wired + compressed` formula Activity Monitor uses, so the numbers line up to the byte. The "Free memory" button runs `/usr/sbin/purge` through the privileged session, waits 800 ms for the kernel to reorganize, and reports the delta. See [MemoryService.swift](Core/Memory/MemoryService.swift).

---

## Build

Requirements: macOS 14 (Sonoma) or later, and the Swift toolchain (Xcode CLT or full Xcode). No `.xcodeproj` needed.

```sh
./run.sh
```

The script builds release with `swift build -c release`, bundles the binary as `CleanMyOwn.app` with a valid `Info.plist`, ad-hoc signs it via `codesign`, kills any prior instance, and launches with `open`.

```sh
pkill -x CleanMyOwn      # stop
```

### Permissions

CleanMyOwn needs two macOS permissions for full functionality:

1. **Full Disk Access** — required to read/clean sandboxed Containers (TCC-protected even from root). The first-launch onboarding wizard walks the user to System Settings → Privacy & Security → Full Disk Access. Detection is live: no app restart required.
2. **Admin mode** (on demand) — required to delete apps in `/Applications` owned by `root:wheel`, `tmutil deletelocalsnapshots`, and Containers with immutability flags. Activated from the in-app banner; one prompt per session.

---

## Roadmap

- [ ] **Privileged helper via `SMAppService.daemon`** — persist admin across sessions, no per-launch re-prompt.
- [ ] **DaisyDisk-style sunburst** — navigable view of which folders consume disk.
- [ ] **`kMDItemLastUsedDate` ranking** — surface large files the user hasn't opened in months.
- [ ] **`lsof` check before delete** — refuse to delete files held by live processes.
- [ ] **Parallel scans with `TaskGroup`** — run the 11 junk categories concurrently.
- [ ] **Developer ID signing + notarization** — proper app icon and name in the TCC permission list.
- [ ] **Optional move-to-Trash mode** — toggle between permanent delete (current default) and reversible Trash.
- [ ] **Menubar quick action** — one-click "Free memory" from the menubar.

---

## Troubleshooting

**"Missing Full Disk Access" persists after granting it.** Hit the refresh button in the banner; if it still doesn't update, quit and relaunch — TCC entitlements are evaluated at process start. The app re-probes on `didBecomeActive` and every 2 seconds, so an active app should refresh automatically.

**Admin mode keeps asking for the password.** Confirm the banner shows "Admin mode active" (green). If you disabled it or the session expired, the next privileged op will prompt again — that's expected.

**Some files still won't delete even with admin + FDA.** They likely carry immutability flags (`uchg` / `schg`). Clear them manually:
```sh
sudo chflags -R noschg /path && sudo rm -rf /path
```

**The app appears in the FDA list without a proper icon.** It's ad-hoc signed (no Developer ID), so macOS lists it by absolute path. Moving or rebuilding the app changes the path, invalidating FDA — re-add it, or sign with a Developer ID for a permanent identity.

---

## License

MIT.

---

Built by [matosr96](https://github.com/matosr96).
