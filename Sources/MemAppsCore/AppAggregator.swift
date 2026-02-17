import Foundation

public struct ProcessRecord: Equatable {
    public let groupKey: String
    public let name: String
    public let bundleId: String?
    public let footprintBytes: UInt64

    public init(groupKey: String, name: String, bundleId: String?, footprintBytes: UInt64) {
        self.groupKey = groupKey
        self.name = name
        self.bundleId = bundleId
        self.footprintBytes = footprintBytes
    }
}

public struct AppAggregate: Codable, Equatable {
    public let name: String
    public let bundleId: String?
    public let footprintBytes: UInt64
    public let processCount: Int

    public init(name: String, bundleId: String?, footprintBytes: UInt64, processCount: Int) {
        self.name = name
        self.bundleId = bundleId
        self.footprintBytes = footprintBytes
        self.processCount = processCount
    }

    enum CodingKeys: String, CodingKey {
        case name
        case bundleId
        case footprintBytes
        case processCount
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let bundleId {
            try container.encode(bundleId, forKey: .bundleId)
        } else {
            try container.encodeNil(forKey: .bundleId)
        }
        try container.encode(footprintBytes, forKey: .footprintBytes)
        try container.encode(processCount, forKey: .processCount)
    }
}

public enum AppAggregator {
    public static func aggregate(_ records: [ProcessRecord]) -> [AppAggregate] {
        var grouped: [String: AggregateBuilder] = [:]

        for record in records {
            if var existing = grouped[record.groupKey] {
                existing.add(record)
                grouped[record.groupKey] = existing
            } else {
                grouped[record.groupKey] = AggregateBuilder(from: record)
            }
        }

        return grouped.values
            .map { $0.asAggregate() }
            .sorted {
                if $0.footprintBytes != $1.footprintBytes {
                    return $0.footprintBytes > $1.footprintBytes
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    public static func filteredTop(_ apps: [AppAggregate], minBytes: UInt64, top: Int) -> [AppAggregate] {
        guard top > 0 else {
            return []
        }

        return apps
            .filter { $0.footprintBytes >= minBytes }
            .prefix(top)
            .map { $0 }
    }
}

public enum MemoryUnits {
    public static func megabytesToBytes(_ megabytes: Double) -> UInt64 {
        guard megabytes > 0 else {
            return 0
        }

        let bytes = megabytes * 1024.0 * 1024.0
        if bytes >= Double(UInt64.max) {
            return UInt64.max
        }
        return UInt64(bytes)
    }
}

private struct AggregateBuilder {
    private var name: String
    private var bundleId: String?
    private var footprintBytes: UInt64
    private var processCount: Int

    init(from record: ProcessRecord) {
        name = record.name
        bundleId = record.bundleId
        footprintBytes = record.footprintBytes
        processCount = 1
    }

    mutating func add(_ record: ProcessRecord) {
        footprintBytes &+= record.footprintBytes
        processCount += 1

        if bundleId == nil, let newBundleId = record.bundleId {
            bundleId = newBundleId
        }

        if name.isEmpty, !record.name.isEmpty {
            name = record.name
        }
    }

    func asAggregate() -> AppAggregate {
        AppAggregate(
            name: name,
            bundleId: bundleId,
            footprintBytes: footprintBytes,
            processCount: processCount
        )
    }
}
