import Foundation

public struct CanonicalBundleIdentity: Equatable {
    public let bundleId: String
    public let name: String

    public init(bundleId: String, name: String) {
        self.bundleId = bundleId
        self.name = name
    }
}

public enum BundleIdentityNormalization {
    public static func canonicalize(bundleId: String, name: String) -> CanonicalBundleIdentity {
        switch bundleId {
        case "org.mozilla.plugincontainer":
            return CanonicalBundleIdentity(bundleId: "org.mozilla.firefox", name: "Firefox")
        default:
            return CanonicalBundleIdentity(bundleId: bundleId, name: name)
        }
    }
}
