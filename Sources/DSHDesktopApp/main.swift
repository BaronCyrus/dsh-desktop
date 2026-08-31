import AppKit
import Darwin
import DSHDesktopCore
import Foundation
import Sparkle
import WebKit

private var managedDSHChildPID: pid_t = 0

private func dshDesktopSignalHandler(_ signalNumber: Int32) {
    let childPID = managedDSHChildPID
    if childPID > 0 {
        Darwin.kill(childPID, SIGTERM)
    }
    Darwin._exit(128 + signalNumber)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var statusPanel: NSVisualEffectView!
    private var spinner: NSProgressIndicator!
    private var statusTitle: NSTextField!
    private var statusDetail: NSTextField!
    private var retryButton: NSButton!
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private let networkSettingsStore = NetworkSettingsStore()
    private var networkSettings = NetworkSettings.unmanaged
    private var networkSettingsPanelController: NetworkSettingsPanelController?
    private var dshProcess: Process?
    private var outputPipe: Pipe?
    private var launchURLParser = LaunchURLParser()
    private var recentDiagnostics: [String] = []
    private var startGeneration = UUID()
    private var launchURLLoaded = false
    private var terminating = false
    private var terminationReplyPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSignalHandlers()
        buildMenu()
        buildWindow()
        configureNetworkAndStart()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationReplyPending {
            return .terminateLater
        }

        terminating = true
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil

        guard let process = dshProcess, process.isRunning else {
            dshProcess = nil
            managedDSHChildPID = 0
            return .terminateNow
        }

        terminationReplyPending = true
        process.terminationHandler = { [weak self, weak process] _ in
            DispatchQueue.main.async {
                guard let self, let process, self.dshProcess === process else { return }
                self.dshProcess = nil
                managedDSHChildPID = 0
                self.completeDeferredTermination()
            }
        }
        process.terminate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak process] in
            guard let self,
                  let process,
                  self.terminationReplyPending,
                  self.dshProcess === process else { return }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            } else {
                self.dshProcess = nil
                managedDSHChildPID = 0
                self.completeDeferredTermination()
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let process = dshProcess, process.isRunning {
            process.terminate()
        }
        dshProcess = nil
        managedDSHChildPID = 0
    }

    private func completeDeferredTermination() {
        guard terminationReplyPending else { return }
        terminationReplyPending = false
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    private func installSignalHandlers() {
        for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
            Darwin.signal(signalNumber, dshDesktopSignalHandler)
        }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 DSH", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let checkForUpdatesItem = NSMenuItem(
            title: "检查更新…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = updaterController
        appMenu.addItem(checkForUpdatesItem)
        appMenu.addItem(.separator())
        let networkSettingsItem = NSMenuItem(
            title: "网络设置…",
            action: #selector(showNetworkSettingsFromMenu(_:)),
            keyEquivalent: ","
        )
        networkSettingsItem.target = self
        appMenu.addItem(networkSettingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 DSH", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "显示")
        let reloadItem = NSMenuItem(title: "重新载入", action: #selector(reloadPage(_:)), keyEquivalent: "r")
        reloadItem.target = self
        viewMenu.addItem(reloadItem)
        viewMenuItem.submenu = viewMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func buildWindow() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        rootView.addSubview(webView)

        statusPanel = NSVisualEffectView()
        statusPanel.translatesAutoresizingMaskIntoConstraints = false
        statusPanel.material = .popover
        statusPanel.blendingMode = .withinWindow
        statusPanel.state = .active
        statusPanel.wantsLayer = true
        statusPanel.layer?.cornerRadius = 14
        statusPanel.layer?.masksToBounds = true

        spinner = NSProgressIndicator()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .regular

        statusTitle = NSTextField(labelWithString: "正在启动 DSH…")
        statusTitle.translatesAutoresizingMaskIntoConstraints = false
        statusTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        statusTitle.alignment = .center

        statusDetail = NSTextField(wrappingLabelWithString: "正在启动本地服务并准备安全认证。")
        statusDetail.translatesAutoresizingMaskIntoConstraints = false
        statusDetail.font = .systemFont(ofSize: 12)
        statusDetail.textColor = .secondaryLabelColor
        statusDetail.alignment = .center
        statusDetail.maximumNumberOfLines = 5

        retryButton = NSButton(title: "重新启动", target: self, action: #selector(restartDSH(_:)))
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.bezelStyle = .rounded
        retryButton.isHidden = true

        statusPanel.addSubview(spinner)
        statusPanel.addSubview(statusTitle)
        statusPanel.addSubview(statusDetail)
        statusPanel.addSubview(retryButton)
        rootView.addSubview(statusPanel)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: rootView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            statusPanel.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            statusPanel.centerYAnchor.constraint(equalTo: rootView.centerYAnchor),
            statusPanel.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
            statusPanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),

            spinner.topAnchor.constraint(equalTo: statusPanel.topAnchor, constant: 22),
            spinner.centerXAnchor.constraint(equalTo: statusPanel.centerXAnchor),

            statusTitle.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 14),
            statusTitle.leadingAnchor.constraint(equalTo: statusPanel.leadingAnchor, constant: 24),
            statusTitle.trailingAnchor.constraint(equalTo: statusPanel.trailingAnchor, constant: -24),

            statusDetail.topAnchor.constraint(equalTo: statusTitle.bottomAnchor, constant: 8),
            statusDetail.leadingAnchor.constraint(equalTo: statusPanel.leadingAnchor, constant: 24),
            statusDetail.trailingAnchor.constraint(equalTo: statusPanel.trailingAnchor, constant: -24),

            retryButton.topAnchor.constraint(equalTo: statusDetail.bottomAnchor, constant: 16),
            retryButton.centerXAnchor.constraint(equalTo: statusPanel.centerXAnchor),
            retryButton.bottomAnchor.constraint(equalTo: statusPanel.bottomAnchor, constant: -20),
        ])

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DSH"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = rootView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureNetworkAndStart() {
        let hadSavedSettings = networkSettingsStore.hasSavedSettings
        let defaultProxyURL = Bundle.main.object(forInfoDictionaryKey: "DSHDefaultProxyURL") as? String
        networkSettings = networkSettingsStore.load(defaultProxyURL: defaultProxyURL)

        if !hadSavedSettings || networkSettings.askOnLaunch {
            showStatus(
                title: "等待网络设置",
                detail: "选择 DSH 启动时使用的网络连接方式。",
                isBusy: false,
                canRetry: false
            )
            let purpose: NetworkSettingsPanelController.Purpose = hadSavedSettings ? .launchPrompt : .initialLaunch
            presentNetworkSettings(purpose: purpose, startAfterDismissal: true)
        } else {
            startDSH()
        }
    }

    private func presentNetworkSettings(
        purpose: NetworkSettingsPanelController.Purpose,
        startAfterDismissal: Bool
    ) {
        guard networkSettingsPanelController == nil else { return }

        let originalSettings = networkSettings
        let controller = NetworkSettingsPanelController(settings: originalSettings, purpose: purpose)
        networkSettingsPanelController = controller
        controller.present(asSheetFor: window) { [weak self] selectedSettings in
            guard let self else { return }
            self.networkSettingsPanelController = nil

            guard let selectedSettings else {
                if startAfterDismissal {
                    self.startDSH()
                }
                return
            }

            do {
                try self.networkSettingsStore.save(selectedSettings)
                self.networkSettings = selectedSettings
                if startAfterDismissal {
                    self.startDSH()
                } else if selectedSettings != originalSettings {
                    self.restartDSH(nil)
                }
            } catch {
                self.showStatus(
                    title: "无法保存网络设置",
                    detail: error.localizedDescription,
                    isBusy: false,
                    canRetry: false
                )
            }
        }
    }

    @objc private func showNetworkSettingsFromMenu(_ sender: Any?) {
        presentNetworkSettings(purpose: .settings, startAfterDismissal: false)
    }

    private func startDSH() {
        let generation = UUID()
        startGeneration = generation
        launchURLLoaded = false
        launchURLParser.reset()
        recentDiagnostics = []
        showStatus(
            title: "正在启动 DSH…",
            detail: "正在选择空闲端口并启动本地服务。",
            isBusy: true,
            canRetry: false
        )

        do {
            let runtime = try RuntimeConfiguration.resolve(networkSettings: networkSettings)
            emitTestSignal("NETWORK_MODE \(networkSettings.mode.rawValue)")
            let process = Process()
            process.executableURL = runtime.executableURL
            process.arguments = ["web", "--no-open", "--port", "0"]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

            process.environment = runtime.environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            outputPipe = pipe
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                    return
                }
                DispatchQueue.main.async {
                    self?.consumeDSHOutput(text, generation: generation)
                }
            }

            process.terminationHandler = { [weak self, weak process] finishedProcess in
                DispatchQueue.main.async {
                    guard let self, let process, self.dshProcess === process else { return }
                    self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                    self.outputPipe = nil
                    self.dshProcess = nil
                    managedDSHChildPID = 0
                    guard !self.terminating else { return }
                    let status = finishedProcess.terminationStatus
                    let diagnostic = self.recentDiagnostics.suffix(6).joined(separator: "\n")
                    let detail = diagnostic.isEmpty
                        ? "本地服务已退出（状态码 \(status)）。"
                        : "本地服务已退出（状态码 \(status)）。\n\(diagnostic)"
                    self.emitTestSignal("PROCESS_EXIT \(status)")
                    self.showStatus(title: "DSH 服务已停止", detail: detail, isBusy: false, canRetry: true)
                }
            }

            dshProcess = process
            try process.run()
            managedDSHChildPID = process.processIdentifier

            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                guard let self,
                      self.startGeneration == generation,
                      !self.launchURLLoaded,
                      self.dshProcess?.isRunning == true else { return }
                self.showStatus(
                    title: "DSH 启动超时",
                    detail: "30 秒内没有收到启动地址。可重新启动；代理未运行时也可能造成插件初始化较慢。",
                    isBusy: false,
                    canRetry: true
                )
            }
        } catch {
            dshProcess = nil
            outputPipe?.fileHandleForReading.readabilityHandler = nil
            outputPipe = nil
            showStatus(title: "无法启动 DSH", detail: error.localizedDescription, isBusy: false, canRetry: true)
        }
    }

    private func consumeDSHOutput(_ chunk: String, generation: UUID) {
        guard generation == startGeneration else { return }

        let cleanChunk = LaunchURLParser.strippingANSI(from: chunk)

        if !launchURLLoaded, let url = launchURLParser.ingest(cleanChunk) {
            launchURLLoaded = true
            showStatus(
                title: "正在认证…",
                detail: "已收到一次性启动凭证，正在建立本机 Web 会话。",
                isBusy: true,
                canRetry: false
            )
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
            return
        }

        for rawLine in cleanChunk.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.contains("?token=") else { continue }
            recentDiagnostics.append(line)
            if recentDiagnostics.count > 20 {
                recentDiagnostics.removeFirst(recentDiagnostics.count - 20)
            }
        }
    }

    private func stopDSH() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        guard let process = dshProcess else { return }
        dshProcess = nil
        if process.isRunning {
            process.terminate()
        }
        managedDSHChildPID = 0
    }

    private func showStatus(title: String, detail: String, isBusy: Bool, canRetry: Bool) {
        statusTitle.stringValue = title
        statusDetail.stringValue = detail
        retryButton.isHidden = !canRetry
        spinner.isHidden = !isBusy
        if isBusy {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        statusPanel.isHidden = false
    }

    @objc private func restartDSH(_ sender: Any?) {
        stopDSH()
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.startDSH()
        }
    }

    @objc private func reloadPage(_ sender: Any?) {
        if webView.url == nil {
            restartDSH(sender)
        } else {
            webView.reload()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, isLoopback(url) else { return }
        statusPanel.isHidden = true
        var cleanComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        cleanComponents?.query = nil
        cleanComponents?.fragment = nil
        emitTestSignal("READY \(cleanComponents?.url?.absoluteString ?? "loopback")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showNavigationError(error)
    }

    private func showNavigationError(_ error: Error) {
        guard !terminating else { return }
        emitTestSignal("NAVIGATION_ERROR \(error.localizedDescription)")
        showStatus(
            title: "无法打开 DSH 页面",
            detail: error.localizedDescription,
            isBusy: false,
            canRetry: true
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let response = navigationResponse.response as? HTTPURLResponse,
           response.statusCode == 401 {
            showStatus(
                title: "DSH 认证失败",
                detail: "本次启动凭证未能建立会话。点击重新启动即可重新签发 token。",
                isBusy: false,
                canRetry: true
            )
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           !isLoopback(url) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if isLoopback(url) {
                webView.load(navigationAction.request)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }

    private func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func emitTestSignal(_ message: String) {
        guard ProcessInfo.processInfo.environment["DSH_DESKTOP_TEST_MODE"] == "1",
              let data = "DSH_DESKTOP_TEST \(message)\n".data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
