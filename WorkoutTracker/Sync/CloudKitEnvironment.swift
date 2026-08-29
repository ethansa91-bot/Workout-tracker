import Foundation

/// Which CloudKit environment this build talks to — Development or Production.
///
/// The two are entirely separate databases with separate schemas, and knowing which one
/// is in play is the difference between a five-minute fix and a long hunt. A field that
/// exists in Development but was never deployed to Production makes every export fail
/// with a `partialFailure` that names no cause at all.
///
/// The rules, in the order CloudKit applies them:
/// 1. An explicit `com.apple.developer.icloud-container-environment` entitlement wins.
///    Setting it to `Production` applies to **every** build including Xcode debug runs,
///    which is rarely what anyone wants.
/// 2. Otherwise the provisioning profile decides: a development profile (the one Xcode
///    signs with, marked by `get-task-allow`) means Development; a distribution profile
///    (TestFlight, App Store) means Production.
/// 3. With no embedded profile to read, the platform decides: the simulator is
///    Development, and a device build that reached the user without a profile came
///    through the store, which is Production.
enum CloudKitEnvironment {

    /// No `unknown` case on purpose. Every branch of `current` resolves to one of these
    /// two, and an "Unknown" reading was actively harmful — it appeared only in store
    /// builds, which are exactly the ones where the environment has to be known.
    enum Kind: String {
        case development = "Development"
        case production = "Production"
    }

    /// Read from the embedded provisioning profile rather than guessed from `#if DEBUG`,
    /// which describes the build configuration and not the CloudKit environment — the two
    /// can disagree.
    static var current: Kind {
        // A *single* value is a genuine pin, applying to every build. An array is not:
        // Xcode's generated profiles carry `["Production", "Development"]` to say both
        // are permitted, and reading the first element there would report Production for
        // an ordinary debug run.
        if case .pinned(let kind) = override { return kind }

        // Nothing pinned, so the signature decides: a debuggable build is development-
        // signed and uses Development; anything else is a distribution build.
        if let allowsDebugging = entitlement(forKey: "get-task-allow") as? Bool {
            return allowsDebugging ? .development : .production
        }

        if profile != nil { return .production }

        // No embedded profile at all. This used to report `.unknown`, which was worse
        // than useless: App Store processing *strips* `embedded.mobileprovision`, so the
        // one screen meant to answer "which environment am I on?" gave up in precisely
        // the TestFlight build where the answer decides whether a schema needs deploying.
        //
        // A device build with no profile can only have come from the store, and store
        // builds are always Production. The simulator is the one other profile-less case,
        // and it is never Production.
        #if targetEnvironment(simulator)
        return .development
        #else
        return .production
        #endif
    }

    /// True only when the entitlement pins one specific environment for every build —
    /// which overrides the signing profile and is almost always unintended. A profile
    /// merely *permitting* both environments is not a pin.
    static var isExplicitlyPinned: Bool {
        if case .pinned = override { return true }
        return false
    }

    private enum Override {
        case pinned(Kind)
        case none
    }

    private static var override: Override {
        guard let raw = entitlement(forKey: "com.apple.developer.icloud-container-environment") else {
            return .none
        }
        // Only a lone value pins. An array with both entries is a permission list.
        let single: String?
        if let string = raw as? String {
            single = string
        } else if let array = raw as? [String], array.count == 1 {
            single = array.first
        } else {
            single = nil
        }

        switch single?.lowercased() {
        case "production": return .pinned(.production)
        case "development": return .pinned(.development)
        default: return .none
        }
    }

    // MARK: - Provisioning profile

    private static func entitlement(forKey key: String) -> Any? {
        profile?["Entitlements"].flatMap { ($0 as? [String: Any])?[key] }
    }

    /// Parses `embedded.mobileprovision`, which is a CMS-signed blob with a plist inside.
    /// Extracting the plist by locating its XML bounds avoids pulling in a CMS decoder for
    /// what is a purely diagnostic read.
    private static let profile: [String: Any?]? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>")
        else { return nil }

        let plistText = String(text[start.lowerBound..<end.upperBound])
        guard let plistData = plistText.data(using: .isoLatin1),
              let parsed = try? PropertyListSerialization.propertyList(
                  from: plistData, options: [], format: nil
              ) as? [String: Any]
        else { return nil }

        return parsed.mapValues { Optional($0) }
    }()
}
