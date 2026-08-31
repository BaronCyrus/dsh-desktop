import DSHDesktopCore
import Foundation

private var checkCount = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checkCount += 1
    guard condition() else {
        FileHandle.standardError.write(Data("Check failed: \(message)\n".utf8))
        exit(1)
    }
}

do {
    var parser = LaunchURLParser()
    let completeURL = parser.ingest("open http://127.0.0.1:3080/?token=abc_123-XYZ\n")
    expect(completeURL?.absoluteString == "http://127.0.0.1:3080/?token=abc_123-XYZ", "complete token URL")

    parser.reset()
    expect(parser.ingest("http://localhost:4512/?tok") == nil, "incomplete URL must wait for another chunk")
    expect(
        parser.ingest("en=split-token")?.absoluteString == "http://localhost:4512/?token=split-token",
        "token URL split across output chunks"
    )

    parser.reset()
    let ansiURL = parser.ingest("\u{001B}[32mhttp://[::1]:9000/?token=secret\u{001B}[0m")
    expect(ansiURL?.absoluteString == "http://[::1]:9000/?token=secret", "ANSI escape removal")

    parser.reset()
    expect(parser.ingest("https://example.com:3080/?token=secret") == nil, "reject non-loopback token URL")

    let pathConfiguration = try RuntimeConfiguration.resolve(environment: [
        "DSH_EXECUTABLE": "/bin/echo",
        "PATH": "/custom/bin",
    ])
    expect(pathConfiguration.executableURL.path == "/bin/echo", "explicit executable")
    expect(
        pathConfiguration.environment["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/custom/bin",
        "standard executable search paths"
    )

    let unmanagedConfiguration = try RuntimeConfiguration.resolve(environment: [
        "DSH_EXECUTABLE": "/bin/echo",
        "HTTP_PROXY": "http://inherited.example:3128",
    ])
    expect(
        unmanagedConfiguration.environment["HTTP_PROXY"] == "http://inherited.example:3128",
        "unmanaged mode preserves inherited proxy"
    )
    expect(
        unmanagedConfiguration.environment["NODE_USE_ENV_PROXY"] == nil,
        "unmanaged mode does not opt Node into proxy handling"
    )

    let customProxy = NetworkSettings(
        mode: .customProxy,
        customProxyURL: " http://127.0.0.1:10808 "
    )
    let proxyConfiguration = try RuntimeConfiguration.resolve(
        environment: ["DSH_EXECUTABLE": "/bin/echo"],
        networkSettings: customProxy
    )
    expect(proxyConfiguration.environment["HTTP_PROXY"] == "http://127.0.0.1:10808", "default HTTP proxy")
    expect(proxyConfiguration.environment["HTTPS_PROXY"] == "http://127.0.0.1:10808", "default HTTPS proxy")
    expect(proxyConfiguration.environment["NODE_USE_ENV_PROXY"] == "1", "Node proxy opt-in")
    expect(proxyConfiguration.environment["NO_PROXY"] == "127.0.0.1,localhost,::1", "loopback proxy bypass")

    let directConfiguration = try RuntimeConfiguration.resolve(
        environment: [
            "DSH_EXECUTABLE": "/bin/echo",
            "HTTP_PROXY": "http://inherited.example:3128",
            "https_proxy": "http://inherited.example:3128",
            "ALL_PROXY": "socks5://inherited.example:1080",
            "NODE_USE_ENV_PROXY": "1",
        ],
        networkSettings: NetworkSettings(mode: .direct)
    )
    expect(directConfiguration.environment["HTTP_PROXY"] == nil, "direct mode removes HTTP proxy")
    expect(directConfiguration.environment["https_proxy"] == nil, "direct mode removes lowercase proxy")
    expect(directConfiguration.environment["ALL_PROXY"] == nil, "direct mode removes all-proxy")
    expect(directConfiguration.environment["NODE_USE_ENV_PROXY"] == nil, "direct mode disables Node proxy opt-in")

    let overrideConfiguration = try RuntimeConfiguration.resolve(
        environment: [
            "DSH_EXECUTABLE": "/bin/echo",
            "DSH_DESKTOP_PROXY_URL": "http://proxy.example:8888",
        ],
        networkSettings: NetworkSettings(mode: .direct)
    )
    expect(
        overrideConfiguration.environment["HTTPS_PROXY"] == "http://proxy.example:8888",
        "runtime proxy overrides build default"
    )

    expect(
        NetworkSettings.initial(defaultProxyURL: "http://127.0.0.1:10808").mode == .customProxy,
        "valid build proxy becomes initial suggestion"
    )
    expect(
        NetworkSettings.initial(defaultProxyURL: "not a proxy").mode == .unmanaged,
        "invalid build proxy falls back to unmanaged"
    )

    let defaultsSuite = "DSHDesktopCoreChecks.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        throw NSError(domain: "DSHDesktopCoreChecks", code: 1)
    }
    defer { defaults.removePersistentDomain(forName: defaultsSuite) }
    let store = NetworkSettingsStore(defaults: defaults)
    expect(!store.hasSavedSettings, "new settings store is unconfigured")
    try store.save(NetworkSettings(mode: .direct, askOnLaunch: true))
    expect(store.hasSavedSettings, "settings store records configuration")
    expect(
        store.load() == NetworkSettings(mode: .direct, askOnLaunch: true),
        "settings store round-trip"
    )

    print("Passed \(checkCount) core checks")
} catch {
    FileHandle.standardError.write(Data("Unexpected check error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
