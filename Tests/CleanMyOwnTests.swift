//
//  CleanMyOwnTests.swift
//  CleanMyOwn
//
//  Tests de la lógica pura más delicada: heurísticas de bundle ID, parsing
//  de salidas de tmutil/simctl/launchctl, allowlist de borrado como root,
//  candidatos del desinstalador, detección de duplicados y ShellRunner
//  (incluida la regresión del deadlock con salidas > 64 KB).
//

import XCTest
@testable import CleanMyOwn

// MARK: - Heurísticas de bundle ID (JunkScanService)

final class BundleIDHeuristicsTests: XCTestCase {
    func testLikelyBundleIDAcceptsTypicalIDs() {
        XCTAssertTrue(JunkScanService.isLikelyBundleID("com.apple.Safari"))
        XCTAssertTrue(JunkScanService.isLikelyBundleID("org.mozilla.firefox"))
        XCTAssertTrue(JunkScanService.isLikelyBundleID("net.whatsapp.WhatsApp.ServiceExtension"))
        XCTAssertTrue(JunkScanService.isLikelyBundleID("io.foo-bar.app_2"))
    }

    func testLikelyBundleIDRejectsPlainNamesAndJunk() {
        XCTAssertFalse(JunkScanService.isLikelyBundleID("Documents"))       // sin punto
        XCTAssertFalse(JunkScanService.isLikelyBundleID("1com.foo"))       // empieza con dígito
        XCTAssertFalse(JunkScanService.isLikelyBundleID("com.foo bar"))    // espacio
        XCTAssertFalse(JunkScanService.isLikelyBundleID(".hidden"))        // un solo segmento
        XCTAssertFalse(JunkScanService.isLikelyBundleID("ñame.app"))       // no ASCII
    }

    func testInstalledOrSubBundleMatching() {
        let installed: Set<String> = ["net.whatsapp.WhatsApp", "com.docker.docker"]
        let sorted = installed.sorted { $0.count > $1.count }

        XCTAssertTrue(JunkScanService.isInstalledOrSubBundle(
            "net.whatsapp.WhatsApp", installed: installed, sorted: sorted))
        // Sub-bundle: prefijo + "."
        XCTAssertTrue(JunkScanService.isInstalledOrSubBundle(
            "net.whatsapp.WhatsApp.ServiceExtension", installed: installed, sorted: sorted))
        // Prefijo sin punto NO es sub-bundle (evita falsos positivos)
        XCTAssertFalse(JunkScanService.isInstalledOrSubBundle(
            "net.whatsapp.WhatsAppHelper", installed: installed, sorted: sorted))
        XCTAssertFalse(JunkScanService.isInstalledOrSubBundle(
            "com.unknown.app", installed: installed, sorted: sorted))
    }

    func testDevCacheDisplayNames() {
        let home = URL(fileURLWithPath: "/Users/test")
        XCTAssertEqual(JunkScanService.devCacheDisplayName(for: home.appendingPathComponent(".npm")), "npm cache")
        XCTAssertEqual(JunkScanService.devCacheDisplayName(for: home.appendingPathComponent("Library/Caches/pip")), "pip cache")
        XCTAssertEqual(JunkScanService.devCacheDisplayName(for: home.appendingPathComponent("go/pkg/mod/cache")), "Go · module cache")
        XCTAssertEqual(JunkScanService.devCacheDisplayName(for: home.appendingPathComponent("Library/Caches/electron-builder")), "electron-builder cache")
        // Desconocido cae al último componente
        XCTAssertEqual(JunkScanService.devCacheDisplayName(for: home.appendingPathComponent("misterio")), "misterio")
    }
}

// MARK: - Parsing de salidas de herramientas

final class ToolOutputParsingTests: XCTestCase {
    func testParseSnapshotIdentifiers() {
        let stdout = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-05-08-123456.local
        com.apple.TimeMachine.2026-05-09-090000.local
        otra línea irrelevante
        """
        XCTAssertEqual(
            JunkScanService.parseSnapshotIdentifiers(from: stdout),
            ["2026-05-08-123456", "2026-05-09-090000"]
        )
    }

    func testParseSnapshotIdentifiersEmptyOutput() {
        XCTAssertEqual(JunkScanService.parseSnapshotIdentifiers(from: ""), [])
        XCTAssertEqual(JunkScanService.parseSnapshotIdentifiers(from: "No snapshots"), [])
    }

    func testPrettySnapshotDate() {
        let pretty = JunkScanService.prettySnapshotDate("2026-05-08-123456")
        XCTAssertNotEqual(pretty, "2026-05-08-123456")  // se pudo parsear
        XCTAssertTrue(pretty.contains("2026"))
        XCTAssertTrue(pretty.contains(":34:"))
        // Inválido → devuelve el raw tal cual
        XCTAssertEqual(JunkScanService.prettySnapshotDate("garbage"), "garbage")
    }

    func testParseLoadedLabels() {
        let stdout = "PID\tStatus\tLabel\n123\t0\tcom.apple.foo\n-\t0\tcom.bar.baz\nlinea sin tabs\n"
        let labels = LaunchAgentService.parseLoadedLabels(from: stdout)
        XCTAssertTrue(labels.contains("com.apple.foo"))
        XCTAssertTrue(labels.contains("com.bar.baz"))
        XCTAssertFalse(labels.contains("linea sin tabs"))
    }

    func testParseLaunchAgentPlist() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let plist: [String: Any] = [
            "Label": "com.test.agent",
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],   // forma diccionario
            "ProgramArguments": ["/usr/bin/true", "-x"]
        ]
        let url = dir.appendingPathComponent("com.test.agent.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url)

        let agent = LaunchAgentService.parsePlist(
            at: url, scope: .userAgent, loadedLabels: ["com.test.agent"], isDisabled: false
        )
        XCTAssertNotNil(agent)
        XCTAssertEqual(agent?.label, "com.test.agent")
        XCTAssertEqual(agent?.runAtLoad, true)
        XCTAssertEqual(agent?.keepAlive, true)
        XCTAssertEqual(agent?.program, "/usr/bin/true")
        XCTAssertEqual(agent?.isLoaded, true)
    }
}

// MARK: - Allowlist de borrado como root (AdminSessionService)

final class RootRemovalAllowlistTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")

    private func allowed(_ path: String) -> Bool {
        AdminSessionService.isAllowedRootRemovalPath(path, home: home)
    }

    func testAllowsDescendantsOfCleanableRoots() {
        XCTAssertTrue(allowed("/Users/test/Library/Caches/com.foo.bar"))
        XCTAssertTrue(allowed("/Users/test/Library/Containers/com.foo.bar"))
        XCTAssertTrue(allowed("/Users/test/.Trash/archivo viejo.zip"))
        XCTAssertTrue(allowed("/Applications/Foo.app"))
        XCTAssertTrue(allowed("/Users/test/Applications/Bar.app"))
    }

    func testRejectsTheRootsThemselves() {
        XCTAssertFalse(allowed("/Users/test/Library"))
        XCTAssertFalse(allowed("/Applications"))
        XCTAssertFalse(allowed("/Users/test/.Trash"))
        XCTAssertFalse(allowed("/"))
    }

    func testRejectsUserDataAndSystemPaths() {
        XCTAssertFalse(allowed("/Users/test/Documents/tesis.pdf"))
        XCTAssertFalse(allowed("/Users/test/Desktop"))
        XCTAssertFalse(allowed("/etc/passwd"))
        XCTAssertFalse(allowed("/System/Library/CoreServices"))
        XCTAssertFalse(allowed("/Users/otro/Library/Caches/x"))
    }

    func testRejectsRelativeAndTraversalPaths() {
        XCTAssertFalse(allowed("Library/Caches/x"))                       // relativo
        XCTAssertFalse(allowed("/Users/test/Library/../Documents/x"))     // ..
        XCTAssertFalse(allowed("/Users/test/Library/./Caches"))           // .
        XCTAssertFalse(allowed(""))
    }

    func testDevCacheRootsAreRemovableExactlyOrDeeper() {
        XCTAssertTrue(allowed("/Users/test/.npm"))
        XCTAssertTrue(allowed("/Users/test/.npm/_cacache"))
        XCTAssertTrue(allowed("/Users/test/.cargo/registry/cache"))
        XCTAssertTrue(allowed("/Users/test/go/pkg/mod/cache"))
        // Pero NO sus padres con datos del usuario
        XCTAssertFalse(allowed("/Users/test/.cargo"))
        XCTAssertFalse(allowed("/Users/test/go"))
        XCTAssertFalse(allowed("/Users/test/go/src/proyecto"))
    }
}

// MARK: - Marcadores del wrapper privilegiado (AdminSessionService)

final class PrivilegedMarkerParsingTests: XCTestCase {
    private func parse(_ lines: [String]) -> (pid: pid_t?, exit: Int32?, output: [String]) {
        var pid: pid_t?
        var exit: Int32?
        var output: [String] = []
        for line in lines {
            AdminSessionService.classify(line: line, childPID: &pid, exitCode: &exit, output: &output)
        }
        return (pid, exit, output)
    }

    func testNormalStream() {
        let r = parse(["__CMO_PID__:4242", "rm: foo: Operation not permitted", "__CMO_EXIT__:1"])
        XCTAssertEqual(r.pid, 4242)
        XCTAssertEqual(r.exit, 1)
        XCTAssertEqual(r.output, ["rm: foo: Operation not permitted"])
    }

    func testPIDIsFirstWinsAndExitIsLastWins() {
        // Un tool malicioso/ruidoso imprime marcadores en medio: el PID real
        // es el primero (el wrapper lo emite antes que nada) y el exit real
        // el último (el wrapper lo emite al final).
        let r = parse([
            "__CMO_PID__:100",
            "__CMO_PID__:999",        // falso → se conserva como output
            "__CMO_EXIT__:0",         // falso intermedio
            "salida normal",
            "__CMO_EXIT__:2"          // el real
        ])
        XCTAssertEqual(r.pid, 100)
        XCTAssertEqual(r.exit, 2)
        XCTAssertEqual(r.output, ["__CMO_PID__:999", "salida normal"])
    }

    func testGarbageMarkersIgnored() {
        let r = parse(["__CMO_PID__:abc", "__CMO_EXIT__:xyz"])
        XCTAssertNil(r.pid)
        XCTAssertNil(r.exit)
        XCTAssertEqual(r.output, ["__CMO_PID__:abc", "__CMO_EXIT__:xyz"])
    }
}

// MARK: - Candidatos del desinstalador (AppCatalogService)

final class AssociatedCandidatesTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")

    func testBundleIDMatchesComeFirstAndAreStrong() {
        let candidates = AppCatalogService.associatedCandidates(
            bundleID: "com.foo.Bar", appName: "Bar App", home: home
        )
        let appSupport = candidates.filter { $0.category == "Application Support" }
        XCTAssertEqual(appSupport.first?.path, "/Users/test/Library/Application Support/com.foo.Bar")
        XCTAssertEqual(appSupport.first?.isNameMatch, false)

        // Variantes por nombre, marcadas como débiles
        XCTAssertTrue(appSupport.contains {
            $0.path == "/Users/test/Library/Application Support/Bar App" && $0.isNameMatch
        })
        XCTAssertTrue(appSupport.contains {
            $0.path == "/Users/test/Library/Application Support/BarApp" && $0.isNameMatch
        })
    }

    func testPreferencesAndLaunchAgentOnlyForBundleID() {
        let withBid = AppCatalogService.associatedCandidates(
            bundleID: "com.foo.Bar", appName: "Bar", home: home
        )
        XCTAssertTrue(withBid.contains {
            $0.category == "Preferences" && $0.path.hasSuffix("com.foo.Bar.plist") && !$0.isNameMatch
        })
        XCTAssertTrue(withBid.contains { $0.category == "Launch Agent" })
        XCTAssertTrue(withBid.contains { $0.category == "Crash Reports" })

        let withoutBid = AppCatalogService.associatedCandidates(
            bundleID: nil, appName: "Bar", home: home
        )
        XCTAssertFalse(withoutBid.contains { $0.category == "Preferences" })
        XCTAssertFalse(withoutBid.contains { $0.category == "Launch Agent" })
        XCTAssertTrue(withoutBid.allSatisfy(\.isNameMatch))
    }
}

// MARK: - Duplicados (LargeFilesService)

final class DuplicateDetectionTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmo-dupes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeFile(_ name: String, content: String) throws -> LargeFile {
        let url = dir.appendingPathComponent(name)
        try content.data(using: .utf8)!.write(to: url)
        return LargeFile(
            url: url,
            sizeBytes: Int64(content.utf8.count),
            modifiedDate: Date(),
            isDirectory: false
        )
    }

    func testDetectsIdenticalFilesAndIgnoresSameSizeDifferentContent() throws {
        let contentA = String(repeating: "A", count: 4096)
        let contentB = String(repeating: "B", count: 4096)   // mismo tamaño, distinto contenido

        let a1 = try makeFile("a1.bin", content: contentA)
        let a2 = try makeFile("a2.bin", content: contentA)
        let b = try makeFile("b.bin", content: contentB)
        let c = try makeFile("c.bin", content: "pequeño")    // tamaño distinto

        let groups = LargeFilesService.findDuplicates(among: [a1, a2, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map(\.url)), Set([a1.url, a2.url]))
        XCTAssertEqual(groups[0].wastedBytes, 4096)          // size * (n-1)
    }

    func testNoDuplicatesAmongDistinctFiles() throws {
        let a = try makeFile("a.bin", content: "uno")
        let b = try makeFile("b.bin", content: "dos!")
        XCTAssertTrue(LargeFilesService.findDuplicates(among: [a, b]).isEmpty)
    }
}

// MARK: - ShellRunner

final class ShellRunnerTests: XCTestCase {
    func testBasicEcho() {
        let result = ShellRunner.runSync("/bin/echo", ["hola"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hola\n")
        XCTAssertEqual(result.stderr, "")
    }

    func testExitCodeAndStderr() {
        let result = ShellRunner.runSync("/bin/sh", ["-c", "echo fallo 1>&2; exit 3"])
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertEqual(result.stderr, "fallo\n")
    }

    func testNonexistentToolReportsError() {
        let result = ShellRunner.runSync("/no/existe", [])
        XCTAssertEqual(result.exitCode, -1)
        XCTAssertFalse(result.stderr.isEmpty)
    }

    /// Regresión: salida mayor que el buffer del pipe (~64 KB) no debe
    /// bloquear (antes se hacía waitUntilExit antes de leer los pipes).
    func testLargeStdoutDoesNotDeadlock() {
        let exp = expectation(description: "termina")
        nonisolated(unsafe) var result: ShellResult?
        DispatchQueue.global().async {
            result = ShellRunner.runSync("/usr/bin/seq", ["1", "200000"])
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
        XCTAssertEqual(result?.exitCode, 0)
        XCTAssertGreaterThan(result?.stdout.utf8.count ?? 0, 1_000_000)
    }

    /// Igual pero inundando stderr mientras stdout queda vacío.
    func testLargeStderrDoesNotDeadlock() {
        let exp = expectation(description: "termina")
        nonisolated(unsafe) var result: ShellResult?
        DispatchQueue.global().async {
            result = ShellRunner.runSync("/bin/sh", ["-c", "/usr/bin/seq 1 200000 1>&2"])
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
        XCTAssertEqual(result?.exitCode, 0)
        XCTAssertGreaterThan(result?.stderr.utf8.count ?? 0, 1_000_000)
        XCTAssertEqual(result?.stdout, "")
    }
}

// MARK: - CPU por delta (SystemInfoService)

final class CPUUsageTests: XCTestCase {
    func testNilSampleIsZero() {
        XCTAssertEqual(SystemInfoService.cpuUsage(current: nil, previous: nil), 0)
    }

    func testFirstSampleFallsBackToBootAverage() {
        let current = CPUTicks(user: 50, system: 25, idle: 25, nice: 0)
        XCTAssertEqual(SystemInfoService.cpuUsage(current: current, previous: nil), 75.0, accuracy: 0.001)
    }

    func testDeltaBetweenSamples() {
        let previous = CPUTicks(user: 100, system: 100, idle: 100, nice: 0)
        let current = CPUTicks(user: 150, system: 125, idle: 225, nice: 0)
        // deltas: user 50, system 25, idle 125 → busy 75 de 200 = 37.5%
        XCTAssertEqual(SystemInfoService.cpuUsage(current: current, previous: previous), 37.5, accuracy: 0.001)
    }

    func testSurvivesUInt32Wraparound() {
        let previous = CPUTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)
        let current = CPUTicks(user: 10, system: 0, idle: 100, nice: 0)
        // delta user = 20 (modular), idle = 100 → 20/120 ≈ 16.67%
        XCTAssertEqual(SystemInfoService.cpuUsage(current: current, previous: previous), 100.0 * 20.0 / 120.0, accuracy: 0.001)
    }
}

// MARK: - MemoryStats

final class MemoryStatsTests: XCTestCase {
    func testUsedBytesFormula() {
        let stats = MemoryStats(
            totalBytes: 16_000, appBytes: 5_000, wiredBytes: 2_000,
            compressedBytes: 1_000, cachedBytes: 3_000, freeBytes: 5_000
        )
        XCTAssertEqual(stats.usedBytes, 8_000)        // app + wired + compressed
        XCTAssertEqual(stats.pressureBytes, 6_000)    // app + compressed
        XCTAssertEqual(stats.pressureFraction, 6_000.0 / 16_000.0, accuracy: 0.0001)
    }
}
