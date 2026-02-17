import AppKit
import Darwin
import Foundation
import MemCore

@main
struct MemCLI {
    static func main() {
        do {
            let parseResult = try CLIOptions.parse(arguments: Array(CommandLine.arguments.dropFirst()))
            switch parseResult {
            case .help:
                print(CLIOptions.helpText)
            case let .run(options):
                try run(with: options)
            }
        } catch let error as CLIParseError {
            fputs("Error: \(error.message)\n\n\(CLIOptions.helpText)\n", stderr)
            exit(2)
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run(with options: CLIOptions) throws {
        var scanner = ProcessScanner(includeOthers: options.includeOthers)
        let scan = scanner.scan()

        let minBytes = MemoryUnits.megabytesToBytes(options.minMB)
        let aggregated = AppAggregator.aggregate(scan.records)
        let filtered = AppAggregator.filteredTop(aggregated, minBytes: minBytes, top: options.top)

        if options.json {
            try printJSON(filtered)
        } else {
            printText(filtered, requestedTop: options.top, rawBytes: options.bytes)
        }

        if options.verbose {
            fputs(
                "Scanned \(scan.stats.totalPIDs) PIDs. Skipped EPERM: \(scan.stats.skippedPermissionDenied), " +
                    "unavailable: \(scan.stats.skippedUnavailable), unmapped: \(scan.stats.skippedUnmapped)\n",
                stderr
            )
        }
    }
}

private struct CLIOptions {
    var top = 30
    var json = false
    var bytes = false
    var includeOthers = false
    var minMB: Double = 0
    var verbose = false

    static let helpText = """
    mem - Print an application memory overview grouped by app

    Usage:
      mem [--top N] [--json] [--bytes] [--include-others] [--min MB] [--verbose]

    Options:
      --top N            Show only top N entries (default: 30)
      --json             Print machine-readable JSON
      --bytes            Print raw bytes (default is human-readable)
      --include-others   Include non-app processes grouped by executable path or "Other"
      --min MB           Minimum app footprint in MB to include
      --verbose          Print scan diagnostics to stderr
      -h, --help         Show this help
    """

    static func parse(arguments: [String]) throws -> CLIParseResult {
        var options = CLIOptions()
        var index = 0

        while index < arguments.count {
            let arg = arguments[index]

            switch arg {
            case "-h", "--help":
                return .help
            case "--json":
                options.json = true
            case "--bytes":
                options.bytes = true
            case "--include-others":
                options.includeOthers = true
            case "--verbose":
                options.verbose = true
            case "--top":
                index += 1
                guard index < arguments.count else {
                    throw CLIParseError("--top requires a value")
                }
                options.top = try parsePositiveInt(arguments[index], flag: "--top")
            case "--min":
                index += 1
                guard index < arguments.count else {
                    throw CLIParseError("--min requires a value")
                }
                options.minMB = try parseNonNegativeDouble(arguments[index], flag: "--min")
            default:
                if let value = arg.splitOnce(prefix: "--top=") {
                    options.top = try parsePositiveInt(value, flag: "--top")
                } else if let value = arg.splitOnce(prefix: "--min=") {
                    options.minMB = try parseNonNegativeDouble(value, flag: "--min")
                } else {
                    throw CLIParseError("Unknown argument: \(arg)")
                }
            }

            index += 1
        }

        return .run(options)
    }

    private static func parsePositiveInt(_ value: String, flag: String) throws -> Int {
        guard let intValue = Int(value), intValue > 0 else {
            throw CLIParseError("\(flag) must be greater than 0")
        }
        return intValue
    }

    private static func parseNonNegativeDouble(_ value: String, flag: String) throws -> Double {
        guard let doubleValue = Double(value), doubleValue >= 0 else {
            throw CLIParseError("\(flag) must be a number >= 0")
        }
        return doubleValue
    }
}

private enum CLIParseResult {
    case help
    case run(CLIOptions)
}

private struct CLIParseError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

private extension String {
    func splitOnce(prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}

private struct ScanStats {
    var totalPIDs = 0
    var skippedPermissionDenied = 0
    var skippedUnavailable = 0
    var skippedUnmapped = 0
}

private struct ScanResult {
    let records: [ProcessRecord]
    let stats: ScanStats
}

private struct AppIdentity {
    let groupKey: String
    let name: String
    let bundleId: String?
}

private struct ProcessScanner {
    private let includeOthers: Bool
    private var identityCache: [pid_t: AppIdentity?] = [:]
    private var parentCache: [pid_t: pid_t?] = [:]
    private var pathCache: [pid_t: String?] = [:]

    init(includeOthers: Bool) {
        self.includeOthers = includeOthers
    }

    mutating func scan() -> ScanResult {
        let pids = listAllPIDs()
        var stats = ScanStats()
        var records: [ProcessRecord] = []
        records.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            stats.totalPIDs += 1

            let footprintResult = readPhysFootprint(pid: pid)
            guard let footprint = footprintResult.bytes else {
                if footprintResult.errorCode == EPERM {
                    stats.skippedPermissionDenied += 1
                } else {
                    stats.skippedUnavailable += 1
                }
                continue
            }

            guard let identity = resolveIdentity(for: pid) else {
                stats.skippedUnmapped += 1
                continue
            }

            records.append(
                ProcessRecord(
                    groupKey: identity.groupKey,
                    name: identity.name,
                    bundleId: identity.bundleId,
                    footprintBytes: footprint
                )
            )
        }

        return ScanResult(records: records, stats: stats)
    }

    private mutating func resolveIdentity(for pid: pid_t) -> AppIdentity? {
        if let cached = identityCache[pid] {
            return cached
        }

        let resolved: AppIdentity?

        if let appIdentity = bundleIdentity(for: pid) {
            resolved = appIdentity
        } else if includeOthers {
            resolved = lineageIdentity(for: pid)
        } else {
            resolved = nil
        }

        identityCache[pid] = resolved
        return resolved
    }

    private func bundleIdentity(for pid: pid_t) -> AppIdentity? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleId = app.bundleIdentifier
        else {
            return nil
        }

        let displayName = app.localizedName ?? bundleId
        let canonical = BundleIdentityNormalization.canonicalize(bundleId: bundleId, name: displayName)
        return AppIdentity(groupKey: "bundle:\(canonical.bundleId)", name: canonical.name, bundleId: canonical.bundleId)
    }

    private mutating func lineageIdentity(for pid: pid_t) -> AppIdentity {
        let lineage = processLineage(from: pid, maxDepth: 48)

        for ancestor in lineage {
            if let appIdentity = bundleIdentity(for: ancestor) {
                return appIdentity
            }
        }

        if let rootPID = lineage.last {
            if let rootPath = executablePathCached(for: rootPID), !rootPath.isEmpty {
                let rootName = URL(fileURLWithPath: rootPath).lastPathComponent
                return AppIdentity(groupKey: "tree:\(rootPath)", name: rootName, bundleId: nil)
            }
        }

        if let ownPath = executablePathCached(for: pid), !ownPath.isEmpty {
            let ownName = URL(fileURLWithPath: ownPath).lastPathComponent
            return AppIdentity(groupKey: "path:\(ownPath)", name: ownName, bundleId: nil)
        }

        return AppIdentity(groupKey: "other", name: "Other", bundleId: nil)
    }

    private mutating func processLineage(from pid: pid_t, maxDepth: Int) -> [pid_t] {
        var lineage: [pid_t] = []
        var seen: Set<pid_t> = []
        var current = pid

        for _ in 0 ..< maxDepth {
            guard current > 0, !seen.contains(current) else {
                break
            }

            lineage.append(current)
            seen.insert(current)

            guard let parent = parentPID(for: current), parent > 1 else {
                break
            }

            current = parent
        }

        return lineage
    }

    private mutating func parentPID(for pid: pid_t) -> pid_t? {
        if let cached = parentCache[pid] {
            return cached
        }

        var info = proc_bsdinfo()
        let size = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_bsdinfo>.stride)
        )

        let resolved: pid_t?
        if size == MemoryLayout<proc_bsdinfo>.stride {
            resolved = pid_t(info.pbi_ppid)
        } else {
            resolved = nil
        }

        parentCache[pid] = resolved
        return resolved
    }

    private mutating func executablePathCached(for pid: pid_t) -> String? {
        if let cached = pathCache[pid] {
            return cached
        }

        let resolved = executablePath(for: pid)
        pathCache[pid] = resolved
        return resolved
    }
}

private func listAllPIDs() -> [pid_t] {
    var capacity = max(Int(proc_listallpids(nil, 0)), 2048)
    let stride = MemoryLayout<pid_t>.stride

    while capacity <= 1_000_000 {
        let buffer = UnsafeMutablePointer<pid_t>.allocate(capacity: capacity)
        defer { buffer.deallocate() }

        let result = Int(proc_listallpids(buffer, Int32(capacity * stride)))
        guard result > 0 else {
            return []
        }

        if result < capacity {
            return (0 ..< result).compactMap { index in
                let pid = buffer[index]
                return pid > 0 ? pid : nil
            }
        }

        capacity *= 2
    }

    return []
}

private func executablePath(for pid: pid_t) -> String? {
    let pidPathBufferSize = Int(MAXPATHLEN) * 4
    var pathBuffer = [CChar](repeating: 0, count: pidPathBufferSize)
    let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
    guard length > 0 else {
        return nil
    }
    return String(cString: pathBuffer)
}

private func readPhysFootprint(pid: pid_t) -> (bytes: UInt64?, errorCode: Int32) {
    var lastError: Int32 = 0

    var infoV4 = rusage_info_v4()
    if readRUsage(pid: pid, flavor: Int32(RUSAGE_INFO_V4), info: &infoV4) {
        return (infoV4.ri_phys_footprint, 0)
    }
    lastError = errno

    var infoV6 = rusage_info_v6()
    if readRUsage(pid: pid, flavor: Int32(RUSAGE_INFO_V6), info: &infoV6) {
        return (infoV6.ri_phys_footprint, 0)
    }
    lastError = errno

    var infoV5 = rusage_info_v5()
    if readRUsage(pid: pid, flavor: Int32(RUSAGE_INFO_V5), info: &infoV5) {
        return (infoV5.ri_phys_footprint, 0)
    }
    lastError = errno

    var infoV3 = rusage_info_v3()
    if readRUsage(pid: pid, flavor: Int32(RUSAGE_INFO_V3), info: &infoV3) {
        return (infoV3.ri_phys_footprint, 0)
    }
    lastError = errno

    var infoV2 = rusage_info_v2()
    if readRUsage(pid: pid, flavor: Int32(RUSAGE_INFO_V2), info: &infoV2) {
        return (infoV2.ri_phys_footprint, 0)
    }
    lastError = errno

    var infoV1 = rusage_info_v1()
    if readRUsage(pid: pid, flavor: Int32(RUSAGE_INFO_V1), info: &infoV1) {
        return (infoV1.ri_phys_footprint, 0)
    }
    lastError = errno

    var infoV0 = rusage_info_v0()
    if readRUsage(pid: pid, flavor: Int32(RUSAGE_INFO_V0), info: &infoV0) {
        return (infoV0.ri_phys_footprint, 0)
    }
    lastError = errno

    return (nil, lastError)
}

private func readRUsage<T>(pid: pid_t, flavor: Int32, info: inout T) -> Bool {
    errno = 0
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPointer in
            proc_pid_rusage(pid, flavor, reboundPointer)
        }
    }
    return status == 0
}

private func printJSON(_ apps: [AppAggregate]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(apps)
    if let output = String(data: data, encoding: .utf8) {
        print(output)
    }
}

private func printText(_ apps: [AppAggregate], requestedTop: Int, rawBytes: Bool) {
    let totalBytes = apps.reduce(UInt64(0)) { $0 &+ $1.footprintBytes }
    let totalFormatted = ByteFormatting.format(bytes: totalBytes, raw: rawBytes)
    print("Total app footprint (top \(requestedTop)): \(totalFormatted)")
    print("")

    let nameHeader = "App Name"
    let bundleHeader = "Bundle ID"
    let footprintHeader = "Total Footprint"
    let processHeader = "Process Count"

    let memoryStrings = apps.map { ByteFormatting.format(bytes: $0.footprintBytes, raw: rawBytes) }
    let processStrings = apps.map { String($0.processCount) }
    let bundleStrings = apps.map { $0.bundleId ?? "-" }

    let nameWidth = max(nameHeader.count, min(40, apps.map(\.name.count).max() ?? nameHeader.count))
    let bundleWidth = max(bundleHeader.count, bundleStrings.map(\.count).max() ?? bundleHeader.count)
    let memoryWidth = max(footprintHeader.count, memoryStrings.map(\.count).max() ?? footprintHeader.count)
    let processWidth = max(processHeader.count, processStrings.map(\.count).max() ?? processHeader.count)

    print(
        "\(rightPad(nameHeader, to: nameWidth)) | " +
            "\(rightPad(bundleHeader, to: bundleWidth)) | " +
            "\(leftPad(footprintHeader, to: memoryWidth)) | " +
            "\(leftPad(processHeader, to: processWidth))"
    )
    print(
        "\(String(repeating: "-", count: nameWidth))-" +
            "+-\(String(repeating: "-", count: bundleWidth))-" +
            "+-\(String(repeating: "-", count: memoryWidth))-" +
            "+-\(String(repeating: "-", count: processWidth))"
    )

    for (index, app) in apps.enumerated() {
        let nameText = rightPad(app.name, to: nameWidth)
        let bundleText = rightPad(bundleStrings[index], to: bundleWidth)
        let memoryText = leftPad(memoryStrings[index], to: memoryWidth)
        let processText = leftPad(processStrings[index], to: processWidth)
        print("\(nameText) | \(bundleText) | \(memoryText) | \(processText)")
    }
}

private func rightPad(_ value: String, to width: Int) -> String {
    if value.count >= width {
        return value
    }
    return value + String(repeating: " ", count: width - value.count)
}

private func leftPad(_ value: String, to width: Int) -> String {
    if value.count >= width {
        return value
    }
    return String(repeating: " ", count: width - value.count) + value
}
