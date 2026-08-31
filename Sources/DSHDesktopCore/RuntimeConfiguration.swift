import Foundation

public enum RuntimeConfigurationError: LocalizedError {
    case executableNotFound

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "未找到 dsh 命令。请先安装 @deepseek-ai/dsh，或设置 DSH_EXECUTABLE。"
        }
    }
}

public struct RuntimeConfiguration {
    public let executableURL: URL
    public let environment: [String: String]

    public static func resolve(
        environment sourceEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        networkSettings: NetworkSettings = .unmanaged,
        fileManager: FileManager = .default
    ) throws -> RuntimeConfiguration {
        var environment = sourceEnvironment
        environment["PATH"] = augmentedPath(sourceEnvironment["PATH"])

        let configuredExecutable = sourceEnvironment["DSH_EXECUTABLE"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }

        let candidates = [configuredExecutable, "/opt/homebrew/bin/dsh", "/usr/local/bin/dsh"]
            .compactMap { $0 }
        guard let executablePath = candidates.first(where: fileManager.isExecutableFile(atPath:)) else {
            throw RuntimeConfigurationError.executableNotFound
        }

        let environmentProxy = sourceEnvironment["DSH_DESKTOP_PROXY_URL"].flatMap(nonEmptyValue)
        let effectiveSettings = environmentProxy.map {
            NetworkSettings(mode: .customProxy, customProxyURL: $0, askOnLaunch: networkSettings.askOnLaunch)
        } ?? networkSettings
        environment = try effectiveSettings.applying(to: environment)

        return RuntimeConfiguration(
            executableURL: URL(fileURLWithPath: executablePath),
            environment: environment
        )
    }

    private static func nonEmptyValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func augmentedPath(_ existingPath: String?) -> String {
        let preferred = ["/opt/homebrew/bin", "/usr/local/bin"]
        let existing = (existingPath ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":")
            .map(String.init)
        return (preferred + existing).reduce(into: [String]()) { paths, path in
            if !paths.contains(path) {
                paths.append(path)
            }
        }.joined(separator: ":")
    }

}
