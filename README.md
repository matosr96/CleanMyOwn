# CleanMyOwn

> **A native macOS cleaner and maintenance app.** SwiftUI, 100% local, no telemetry. Inspired by CleanMyMac.

[![Download](https://img.shields.io/github/v/release/matosr96/CleanMyOwn?color=success&label=download)](https://github.com/matosr96/CleanMyOwn/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-✓-blueviolet.svg)](https://developer.apple.com/swiftui/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](#license)

CleanMyOwn is a SwiftUI desktop app that scans, cleans, and maintains a macOS system end to end: junk caches, orphaned app data, large files and duplicates, uninstalling apps with their leftovers, login items, and live memory pressure. It talks directly to Mach (`host_statistics64`, `vm_statistics64`), TCC, and Authorization Services — no Electron, no telemetry. Privileged work runs through a persistent in-process auth session, or through an **optional, narrowly-scoped `SMAppService` helper** if you want zero password prompts.

---

## Install

[**Download the latest release**](https://github.com/matosr96/CleanMyOwn/releases/latest) — macOS 14 or later, Apple Silicon only (the build is not universal). Open the `.dmg` and drag the app to Applications.

The release is **ad-hoc signed and not notarized**, so Gatekeeper refuses it on first launch with an "unidentified developer" message. Right-click the app in Applications and choose **Open**, then **Open** again. If macOS still blocks it:

```sh
xattr -dr com.apple.quarantine /Applications/CleanMyOwn.app
```

Because an ad-hoc signature changes on every build, the Full Disk Access grant and the helper approval do not survive replacing the app — you will grant them again after each update. Building locally with a signing identity avoids that; see [Build](#build).

---

## Why

Most macOS cleaners fall into one of three traps: they ship an always-on privileged helper that can run anything as root, they shell out to `osascript` and trigger a password prompt for every action, or they delete blindly and leave the Dock full of zombie icons. CleanMyOwn skips all three: no prompt-per-action, process-aware deletes, and root access that is either a session-scoped `AuthorizationRef` or an opt-in helper that only understands four narrow verbs gated by an allowlist.

The interesting problems in this domain aren't UI — they're **state**: which bundle IDs are actually still installed, which processes hold a `.app` open, which files are protected by TCC even from root, which auth session is still valid. Most of the engineering work here is about answering those questions correctly and cheaply.

---

## Highlights

- **11-category junk scanner** including dev caches (npm, pnpm, pip, Homebrew, Cargo, Gradle, Maven, CocoaPods, Composer, Go, Electron — 21 known paths), iOS Simulator caches, Time Machine local snapshots, and obsolete simulators.
- **Smart orphan detection** for sandboxed app data using `mdfind` + prefix-matching on bundle IDs — no false positives on installed sub-bundles like `net.whatsapp.WhatsApp.ServiceExtension`.
- **Uninstaller that closes live processes first** via dual path/bundle-ID match, then `terminate()` with 2s grace, then `forceTerminate()`. Detects associated files across 12 standard locations.
- **3-pass duplicate detection** (size bucket → 1MB quick hash → full SHA-256 streaming). Less than 5% of scanned files end up fully hashed in practice.
- **Persistent admin session** via long-lived `AuthorizationRef` — one password prompt per app launch, not per action. Deleting 50 protected apps in a row = 1 prompt.
- **Optional zero-prompt mode** via an `SMAppService.daemon` helper with exactly four verbs (`removeItems` within an allowlist, `deleteTimeMachineSnapshot` with validated format, `purgeMemory`, `version`) — never "run this command as root". Survives app restarts; uninstallable from the same banner.
- **Reversible deletes on demand**: a persistent move-to-Trash toggle across Cleaner, Uninstaller, and Large Files (with honest exceptions — snapshots, simulators, Trash itself, and root-owned files stay permanent).
- **Live Full Disk Access detection** via TCC.db readability probe + 2s polling + `NSApplication.didBecomeActiveNotification` — no app restart required after granting.
- **Memory monitor that matches Activity Monitor** by calling `vm_statistics64` directly with the same `active + wired + compressed` formula.
- **Native end to end:** SwiftUI + AppKit, no Electron, no telemetry.

---

## Tech stack

| Layer | Choice |
|---|---|
| UI | SwiftUI (`@StateObject`, `@EnvironmentObject`, custom modifiers) |
| System integration | AppKit (`NSWorkspace`, `NSRunningApplication`), Mach syscalls (`host_statistics64`, `vm_statistics64`) |
| Privileged operations | Authorization Services (`AuthorizationCreate` + `AuthorizationExecuteWithPrivileges`); optional `SMAppService.daemon` + `NSXPCConnection` helper |
| Hashing | CryptoKit `SHA256` streaming, 4MB chunks |
| Concurrency | `Task.detached` with explicit cancellation, `@Published` over Combine |
| CLI bridges | `launchctl`, `tmutil`, `xcrun simctl`, `mdfind` — all via a deadlock-safe `ShellRunner` |
| Testing | XCTest suite over the pure logic (`swift test`) |
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
├── Shared/                           # library shared by app AND helper
│   ├── HelperProtocol.swift          # XPC contract (4 narrow verbs)
│   ├── RootRemovalPolicy.swift       # rm-as-root allowlist (enforced both sides)
│   └── ShellRunner.swift             # deadlock-safe Process wrapper
├── Helper/main.swift                 # root daemon (SMAppService + NSXPCListener)
├── Modules/                          # one folder per feature view
│   ├── Dashboard/  JunkCleaner/  Uninstaller/
│   ├── LargeFiles/ LoginItems/   MemoryFreer/
├── UI/
│   ├── Components/                   # ProgressRing, Confetti, Shimmer, …
│   ├── Onboarding/OnboardingView.swift  # 3-step FDA wizard
│   └── Theme/                        # palette, typography, animations
├── Tests/                            # XCTest suite over the pure logic
├── Package.swift                     # SwiftPM: app + helper + shared lib + tests
└── run.sh                            # build → bundle (app+helper+daemon plist) → codesign → launch
```

---

## Engineering decisions worth a look

A handful of choices that aren't obvious from the file tree:

**Persistent `AuthorizationRef` instead of per-call `osascript`.** Each `osascript do shell script with administrator privileges` invocation runs in its own process and does not share the auth cache, so a 50-app batch uninstall would prompt 50 times. The app holds a single `AuthorizationRef` inside its own process — shared app-wide as an `EnvironmentObject`, so switching modules never re-prompts — calls `AuthorizationCopyRights` once, and then routes every privileged command (including `purge`) through `AuthorizationExecuteWithPrivileges`. One password prompt per session. See [AdminSessionService.swift](Core/Permissions/AdminSessionService.swift).

**Real exit codes out of a deprecated API.** `AuthorizationExecuteWithPrivileges` exposes neither the child PID nor its exit status, which makes "did the privileged delete actually work?" unanswerable. Every privileged command therefore runs through a `/bin/sh` wrapper that emits two markers down the communication pipe: its own PID (first line) and the tool's real exit code (last line, `printf`-prefixed with a newline so an unterminated tool output can't swallow it). The tool and its arguments travel as positional parameters (`$0`/`$@`) the shell never parses — zero injection surface. The PID enables reaping exactly that child instead of a global `waitpid(-1)` that would steal exit statuses from concurrent `Process` instances (`mdfind`, `simctl`, `launchctl`).

**Root deletions gated by an allowlist.** `removeAsRoot` refuses any path outside the roots the app actually cleans (`~/Library`, `~/.Trash`, `/Applications`, `~/Applications`, and specific dev-cache directories) — and refuses the roots themselves, `/`, relative paths, and anything containing `.` or `..` components. A bug in any caller degrades into a rejected request instead of an arbitrary `rm -rf` as root.

**Heuristics never pre-select.** After a scan, only regenerable categories (caches, logs, trash, Xcode artifacts) come pre-checked. Orphaned app data, Time Machine snapshots, and obsolete simulators stay unchecked — orphan detection is a heuristic, and one false positive would delete the preferences or licenses of an installed app. Same in the uninstaller: files matched only by app *name* get a "POR NOMBRE" badge and stay unchecked, since a generic name can collide with another app's data. Selection is built incrementally with `formUnion`, so anything the user unchecks mid-scan stays unchecked.

**FDA status probed via TCC.db, not entitlement APIs.** macOS does not expose a public API to ask "do I have Full Disk Access?" The reliable proxy is whether `/Library/Application Support/com.apple.TCC/TCC.db` is readable — it requires FDA to open. `PermissionsMonitor` does that probe on a 2-second timer and on `NSApplication.didBecomeActiveNotification`, so the UI updates the instant the user grants permission in System Settings without an app restart. See [PermissionsMonitor.swift](Core/Permissions/PermissionsMonitor.swift).

**Orphan detection with prefix matching on bundle IDs.** The naïve version — "delete `~/Library/Containers/<bid>` if no app with that bundle ID is installed" — flags real sub-bundles like `net.whatsapp.WhatsApp.ServiceExtension` as orphans. The scanner pre-computes the set of installed bundle IDs via `mdfind`, then walks each app bundle for `Contents/PlugIns/*.appex`, `XPCServices/*.xpc`, and `LoginItems/*.app`. A candidate is an orphan only if no installed ID is a `.`-separated prefix of it. See [JunkScanService.swift](Core/Cleaner/JunkScanService.swift).

**3-pass duplicate pipeline.** Hashing every large file is wasteful — most files have unique sizes. The pipeline groups by exact size, drops singletons, hashes only the first 1 MB to drop accidental size matches, and only then runs full SHA-256 streamed in 4 MB chunks. Empirically <5% of candidates reach the third pass. See [LargeFilesService.swift](Core/Files/LargeFilesService.swift).

**Automatic privileged fallback on delete failures.** `FileManager.removeItem` can fail silently on sandboxed Containers even with FDA granted, because TCC owns them with flags `removeItem` won't override. When admin mode is active, a failed delete retries as a privileged `rm -rf` through the persistent `AuthorizationRef`. After every delete the app re-checks `FileManager.fileExists(atPath:)` and only updates the in-memory list when the path actually disappeared — so the UI never lies about disk state.

**Process termination before uninstall.** Deleting an open `.app` leaves zombie Dock icons and locked handles. The uninstaller matches running processes two ways: by executable path inside the bundle (catches helpers whose bundle ID does not match the parent app) and by exact bundle ID plus prefix sub-bundles. It calls `terminate()` first, waits 2 seconds, then `forceTerminate()` on holdouts, then sleeps 400 ms for WindowServer to clear icons before the delete. See [AppCatalogService.swift](Core/Apps/AppCatalogService.swift).

**Memory readings via direct Mach syscalls.** `MemoryService` calls `host_statistics64(HOST_VM_INFO64, …)` and applies the same `active + wired + compressed` formula Activity Monitor uses, so the numbers line up to the byte. The "Free memory" button runs `/usr/sbin/purge` through the privileged session, waits 800 ms for the kernel to reorganize, and reports the delta. See [MemoryService.swift](Core/Memory/MemoryService.swift).

**A privileged helper that can't be repurposed.** The optional `SMAppService.daemon` helper deliberately exposes no generic "execute" verb — only `removeItems`, `deleteTimeMachineSnapshot`, `purgeMemory`, and `version`. The allowlist is re-evaluated **inside the helper** with the home directory derived from the connecting client's euid via `getpwuid` (never from a client-supplied path), and connections are only accepted from the console user (owner of `/dev/console`, never root). The peer code-signing requirement adapts to how the helper itself was signed: with a team identity it demands *Apple certificate chain + bundle identifier + the helper's own Team ID* (introspected at runtime), so an ad-hoc binary claiming the identifier no longer qualifies; only in the ad-hoc dev fallback does it degrade to identifier-only — which is why the narrow verbs + server-side allowlist carry the real security weight regardless. See [Helper/main.swift](Helper/main.swift) and [RootRemovalPolicy.swift](Shared/RootRemovalPolicy.swift).

**Move-to-Trash with honest exceptions.** The persistent toggle (`@AppStorage`) switches `FileManager.removeItem` for `trashItem` across all three deletion surfaces. What it deliberately does *not* pretend to do: root cannot move files into a user's Trash, so privileged deletes stay permanent (and the trash mode never silently escalates to root); emptying the Trash is permanent by nature; `tmutil` snapshots and `simctl` deletes have no Trash concept. Each confirm dialog states which rule applies before anything is deleted.

---

## Build

Requirements: macOS 14 (Sonoma) or later, and the Swift toolchain (Xcode CLT or full Xcode). No `.xcodeproj` needed.

```sh
./run.sh
```

The script builds release with `swift build -c release`, bundles app + privileged helper + daemon plist as `CleanMyOwn.app`, signs, kills any prior instance, and launches with `open`.

**Signing is auto-detected**: `Developer ID Application` if present, else `Apple Development`, else ad-hoc (override with `CODESIGN_IDENTITY=... ./run.sh`). A real identity matters beyond cosmetics: the signature stays stable across rebuilds, so the **Full Disk Access grant and the helper approval survive every rebuild**, and the helper's XPC requirement upgrades from identifier-only to *Apple chain + same Team ID* (it introspects its own signing team at runtime via `SecCodeCopySigningInformation`).

`./run.sh --notarize` zips, submits via `notarytool` (keychain profile `CleanMyOwnNotary`), and staples — it requires a `Developer ID Application` certificate, which means the paid Apple Developer Program; with a free personal team the notary service returns 403.

```sh
pkill -x CleanMyOwn      # stop
```

### Tests

```sh
swift test
```

The suite covers the logic where a bug costs user data, without touching the system: bundle-ID heuristics and orphan detection, `tmutil`/`launchctl`/plist parsing, the root-removal allowlist matrix, uninstaller candidates (bundle-ID vs name matches), hash-based duplicate detection over temp files, CPU-delta math including `UInt32` wraparound, privileged-wrapper marker parsing (first-PID-wins / last-exit-wins against spoofed markers), and a regression test that floods `ShellRunner` with >1 MB per pipe to prove the pipe-buffer deadlock stays dead.

### Permissions

CleanMyOwn needs two macOS permissions for full functionality:

1. **Full Disk Access** — required to read/clean sandboxed Containers (TCC-protected even from root). The first-launch onboarding wizard walks the user to System Settings → Privacy & Security → Full Disk Access. Detection is live: no app restart required.
2. **Admin mode** (on demand) — required to delete apps in `/Applications` owned by `root:wheel`, `tmutil deletelocalsnapshots`, and Containers with immutability flags. Activated from the in-app banner; one prompt per session.
3. **Background helper** (optional) — "Instalar asistente" in the Cleaner/Uninstaller banners registers the `SMAppService` daemon. macOS will ask for approval under System Settings → General → Login Items & Extensions → *Allow in the Background*. Once approved, privileged operations run with no password at all and the grant survives app restarts. Uninstall it anytime from the same banner.

---

## Roadmap

- [x] **Privileged helper via `SMAppService.daemon`** — persist admin across sessions, no per-launch re-prompt. Narrow XPC verbs + server-side allowlist.
- [x] **Optional move-to-Trash mode** — persistent toggle between permanent delete (default) and reversible Trash.
- [ ] **DaisyDisk-style sunburst** — navigable view of which folders consume disk.
- [ ] **`kMDItemLastUsedDate` ranking** — surface large files the user hasn't opened in months.
- [ ] **`lsof` check before delete** — refuse to delete files held by live processes.
- [ ] **Parallel scans with `TaskGroup`** — run the 11 junk categories concurrently.
- [ ] **Developer ID signing + notarization** — proper app icon in the TCC list and a code-signing requirement with real teeth for the helper.
- [ ] **Menubar quick action** — one-click "Free memory" from the menubar.

---

## Troubleshooting

**"Missing Full Disk Access" persists after granting it.** Hit the refresh button in the banner; if it still doesn't update, quit and relaunch — TCC entitlements are evaluated at process start. The app re-probes on `didBecomeActive` and every 2 seconds, so an active app should refresh automatically.

**Admin mode keeps asking for the password.** Confirm the banner shows "Admin mode active" (green). If you disabled it or the session expired, the next privileged op will prompt again — that's expected.

**Some files still won't delete even with admin + FDA.** They likely carry immutability flags (`uchg` / `schg`). Clear them manually:
```sh
sudo chflags -R noschg /path && sudo rm -rf /path
```

**FDA or helper approval lost after rebuilding.** Only happens with the ad-hoc fallback (no signing identity in the keychain): the ad-hoc signature changes on every build, so TCC and `SMAppService` treat each build as a new app. Fix: have an `Apple Development` (or `Developer ID`) certificate in the keychain — `run.sh` picks it up automatically and grants persist across rebuilds.

**The helper stays in "requires approval".** Open System Settings → General → Login Items & Extensions and enable CleanMyOwn under *Allow in the Background*, then hit the ↻ button in the banner. After rebuilding with a changed signature you may need to uninstall and reinstall the helper (the daemon binary inside the bundle changed).

---

## License

MIT.

---

Built by [matosr96](https://github.com/matosr96).
