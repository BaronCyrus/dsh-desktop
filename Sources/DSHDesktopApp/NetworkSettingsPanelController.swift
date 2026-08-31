import AppKit
import DSHDesktopCore

final class NetworkSettingsPanelController: NSObject, NSTextFieldDelegate {
    enum Purpose {
        case initialLaunch
        case launchPrompt
        case settings
    }

    private let purpose: Purpose
    private let alert = NSAlert()
    private let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let proxyField = NSTextField()
    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let validationLabel = NSTextField(labelWithString: "")
    private let askOnLaunchCheckbox = NSButton(
        checkboxWithTitle: "每次启动 DSH 时询问",
        target: nil,
        action: nil
    )

    init(settings: NetworkSettings, purpose: Purpose) {
        self.purpose = purpose
        super.init()
        configureAlert(settings: settings)
    }

    func present(
        asSheetFor window: NSWindow,
        completion: @escaping (NetworkSettings?) -> Void
    ) {
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else {
                completion(nil)
                return
            }
            completion(try? self.currentSettings().validated())
        }
    }

    private func configureAlert(settings: NetworkSettings) {
        alert.alertStyle = .informational
        alert.messageText = purpose == .settings ? "网络设置" : "选择 DSH 的网络连接方式"
        alert.informativeText = informativeText
        alert.addButton(withTitle: primaryButtonTitle)
        if purpose != .initialLaunch {
            alert.addButton(withTitle: purpose == .launchPrompt ? "使用原设置" : "取消")
        }

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 184))

        let modeLabel = NSTextField(labelWithString: "连接方式：")
        modeLabel.frame = NSRect(x: 0, y: 151, width: 82, height: 22)
        accessoryView.addSubview(modeLabel)

        modePopup.frame = NSRect(x: 88, y: 146, width: 330, height: 30)
        modePopup.addItems(withTitles: ["DSH 默认（不干预）", "强制直连", "自定义代理"])
        modePopup.selectItem(at: Self.index(for: settings.mode))
        modePopup.target = self
        modePopup.action = #selector(modeChanged(_:))
        accessoryView.addSubview(modePopup)

        descriptionLabel.frame = NSRect(x: 88, y: 108, width: 330, height: 34)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.maximumNumberOfLines = 2
        accessoryView.addSubview(descriptionLabel)

        let proxyLabel = NSTextField(labelWithString: "代理地址：")
        proxyLabel.frame = NSRect(x: 0, y: 76, width: 82, height: 22)
        accessoryView.addSubview(proxyLabel)

        proxyField.frame = NSRect(x: 88, y: 72, width: 330, height: 26)
        proxyField.placeholderString = "http://127.0.0.1:10808"
        proxyField.stringValue = settings.customProxyURL
        proxyField.delegate = self
        accessoryView.addSubview(proxyField)

        validationLabel.frame = NSRect(x: 88, y: 46, width: 330, height: 20)
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: 11)
        accessoryView.addSubview(validationLabel)

        askOnLaunchCheckbox.frame = NSRect(x: 84, y: 8, width: 334, height: 24)
        askOnLaunchCheckbox.state = settings.askOnLaunch ? .on : .off
        accessoryView.addSubview(askOnLaunchCheckbox)

        alert.accessoryView = accessoryView
        updateControlState()
    }

    private var informativeText: String {
        switch purpose {
        case .initialLaunch:
            return "该选择会保存在本机，之后可从 DSH 菜单随时修改。"
        case .launchPrompt:
            return "可临时修改本次及后续启动使用的连接方式。"
        case .settings:
            return "连接方式发生变化后，会自动重启本地 DSH 服务并重新认证。"
        }
    }

    private var primaryButtonTitle: String {
        switch purpose {
        case .initialLaunch:
            return "保存并启动"
        case .launchPrompt:
            return "应用并启动"
        case .settings:
            return "保存"
        }
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        updateControlState()
    }

    func controlTextDidChange(_ notification: Notification) {
        updateControlState()
    }

    private func updateControlState() {
        let customProxySelected = selectedMode == .customProxy
        proxyField.isEnabled = customProxySelected

        switch selectedMode {
        case .unmanaged:
            descriptionLabel.stringValue = "不修改代理环境，让 DSH 按自身配置运行。"
        case .direct:
            descriptionLabel.stringValue = "清除常见代理环境变量后启动 DSH。"
        case .customProxy:
            descriptionLabel.stringValue = "把指定的 HTTP/HTTPS 代理传给 DSH；本机页面始终绕过代理。"
        }

        if customProxySelected {
            do {
                _ = try currentSettings().validated()
                validationLabel.stringValue = ""
                alert.buttons.first?.isEnabled = true
            } catch {
                validationLabel.stringValue = error.localizedDescription
                alert.buttons.first?.isEnabled = false
            }
        } else {
            validationLabel.stringValue = ""
            alert.buttons.first?.isEnabled = true
        }
    }

    private var selectedMode: NetworkMode {
        switch modePopup.indexOfSelectedItem {
        case 1:
            return .direct
        case 2:
            return .customProxy
        default:
            return .unmanaged
        }
    }

    private func currentSettings() -> NetworkSettings {
        NetworkSettings(
            mode: selectedMode,
            customProxyURL: proxyField.stringValue,
            askOnLaunch: askOnLaunchCheckbox.state == .on
        )
    }

    private static func index(for mode: NetworkMode) -> Int {
        switch mode {
        case .unmanaged:
            return 0
        case .direct:
            return 1
        case .customProxy:
            return 2
        }
    }
}
