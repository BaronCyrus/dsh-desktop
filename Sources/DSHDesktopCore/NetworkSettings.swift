import Foundation

public enum NetworkMode: String, CaseIterable {
    case unmanaged
    case direct
    case customProxy
}

public enum NetworkSettingsError: LocalizedError {
    case invalidProxyURL

    public var errorDescription: String? {
        switch self {
        case .invalidProxyURL:
            return "请输入有效的 HTTP 或 HTTPS 代理地址，例如 http://127.0.0.1:10808。"
        }
    }
}

public struct NetworkSettings: Equatable {
    public let mode: NetworkMode
    public let customProxyURL: String
    public let askOnLaunch: Bool

    public static let unmanaged = NetworkSettings(
        mode: .unmanaged,
        customProxyURL: "",
        askOnLaunch: false
    )

    public init(mode: NetworkMode, customProxyURL: String = "", askOnLaunch: Bool = false) {
        self.mode = mode
        self.customProxyURL = customProxyURL
        self.askOnLaunch = askOnLaunch
    }

    public static func initial(defaultProxyURL: String?) -> NetworkSettings {
        let candidate = NetworkSettings(
            mode: .customProxy,
            customProxyURL: defaultProxyURL ?? ""
        )
        return (try? candidate.validated()) ?? .unmanaged
    }

    public func validated() throws -> NetworkSettings {
        let trimmedProxyURL = customProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .customProxy else {
            return NetworkSettings(
                mode: mode,
                customProxyURL: trimmedProxyURL,
                askOnLaunch: askOnLaunch
            )
        }

        guard let components = URLComponents(string: trimmedProxyURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else {
            throw NetworkSettingsError.invalidProxyURL
        }

        return NetworkSettings(
            mode: mode,
            customProxyURL: trimmedProxyURL,
            askOnLaunch: askOnLaunch
        )
    }

    public func applying(to sourceEnvironment: [String: String]) throws -> [String: String] {
        let settings = try validated()
        var environment = sourceEnvironment

        switch settings.mode {
        case .unmanaged:
            break
        case .direct:
            for key in Self.proxyEnvironmentKeys + ["NODE_USE_ENV_PROXY"] {
                environment.removeValue(forKey: key)
            }
        case .customProxy:
            for key in Self.proxyEnvironmentKeys {
                environment.removeValue(forKey: key)
            }
            for key in ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"] {
                environment[key] = settings.customProxyURL
            }
            environment["NODE_USE_ENV_PROXY"] = "1"
            let noProxy = environment["NO_PROXY"] ?? environment["no_proxy"]
            let merged = Self.mergedNoProxy(noProxy)
            environment["NO_PROXY"] = merged
            environment["no_proxy"] = merged
        }

        return environment
    }

    private static let proxyEnvironmentKeys = [
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
        "http_proxy", "https_proxy", "all_proxy",
        "npm_config_proxy", "npm_config_https_proxy",
    ]

    private static func mergedNoProxy(_ existingValue: String?) -> String {
        let required = ["127.0.0.1", "localhost", "::1"]
        let existing = (existingValue ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return (required + existing).reduce(into: [String]()) { entries, entry in
            if !entries.contains(entry) {
                entries.append(entry)
            }
        }.joined(separator: ",")
    }
}

public final class NetworkSettingsStore {
    private enum Key {
        static let configured = "networkSettings.configured"
        static let mode = "networkSettings.mode"
        static let customProxyURL = "networkSettings.customProxyURL"
        static let askOnLaunch = "networkSettings.askOnLaunch"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasSavedSettings: Bool {
        defaults.bool(forKey: Key.configured)
    }

    public func load(defaultProxyURL: String? = nil) -> NetworkSettings {
        guard hasSavedSettings,
              let rawMode = defaults.string(forKey: Key.mode),
              let mode = NetworkMode(rawValue: rawMode) else {
            return .initial(defaultProxyURL: defaultProxyURL)
        }

        let settings = NetworkSettings(
            mode: mode,
            customProxyURL: defaults.string(forKey: Key.customProxyURL) ?? "",
            askOnLaunch: defaults.bool(forKey: Key.askOnLaunch)
        )
        return (try? settings.validated()) ?? .unmanaged
    }

    public func save(_ settings: NetworkSettings) throws {
        let validated = try settings.validated()
        defaults.set(validated.mode.rawValue, forKey: Key.mode)
        defaults.set(validated.customProxyURL, forKey: Key.customProxyURL)
        defaults.set(validated.askOnLaunch, forKey: Key.askOnLaunch)
        defaults.set(true, forKey: Key.configured)
    }
}
