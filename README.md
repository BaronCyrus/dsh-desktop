# DSH Desktop

[![CI](https://github.com/BaronCyrus/dsh-desktop/actions/workflows/ci.yml/badge.svg)](https://github.com/BaronCyrus/dsh-desktop/actions/workflows/ci.yml)

一个原生 macOS 外壳：启动本机 `dsh web`，读取每次启动生成的 token 地址，并在持久化的 WebKit 会话中打开 DSH。用户无需手动复制 token，也不会再与固定的 `3080` 端口冲突。

> 这是一个非官方社区项目，不隶属于 DeepSeek。DSH、DeepSeek 名称及相关标识的权利归其各自权利人所有。

当前版本仅支持 macOS；项目名称采用跨平台形式，为未来的 Windows 和其他桌面平台预留空间。

## 功能

- 每次启动自动执行 `dsh web --no-open --port 0`
- 自动解析并打开一次性 token URL
- 首次启动选择网络模式，并可选择每次启动时询问
- 从应用菜单随时切换“不干预 / 强制直连 / 自定义代理”
- 使用动态空闲端口，避免 `EADDRINUSE`
- 关闭应用时一并停止其启动的 DSH 子进程
- 使用 macOS 持久化 WebKit Cookie
- 可从“DSH → 检查更新…”安全检查、下载并安装新版本
- 支持 Apple Silicon 与 Intel 通用二进制
- 可生成可拖入“应用程序”目录的 DMG

## 环境要求

- macOS 14 或更高版本
- Xcode Command Line Tools
- 已安装可用的 `dsh` 命令，例如：

  ```bash
  npm install -g @deepseek-ai/dsh
  ```

应用依次查找 `DSH_EXECUTABLE`、`/opt/homebrew/bin/dsh` 和 `/usr/local/bin/dsh`。

## 开发与构建

```bash
git clone https://github.com/BaronCyrus/dsh-desktop.git
cd dsh-desktop
make test
make build
make run
```

默认生成 Intel + Apple Silicon 通用应用：

```text
build/DSH.app
```

只构建当前架构可加快本地迭代：

```bash
ARCHITECTURES="$(uname -m)" make build
```

## 网络设置

首次启动会显示原生网络设置面板，之后可从菜单栏的“DSH → 网络设置…”再次打开：

- **DSH 默认（不干预）**：不修改代理变量，让 DSH 按自身环境和配置运行。
- **强制直连**：清除常见 HTTP、HTTPS、ALL_PROXY 与 npm 代理变量。
- **自定义代理**：在启动 DSH 前注入指定的 HTTP/HTTPS 代理，本机回环地址始终绕过代理。

选择“每次启动 DSH 时询问”后，每次打开应用都会先显示该面板。保存新的连接方式会自动重启 DSH 服务并重新签发 token。

### 本机构建默认值

公开构建默认不写入代理。若本机 DSH 必须通过代理访问服务，可在构建时提供首次启动的建议值：

```bash
DEFAULT_PROXY_URL="http://127.0.0.1:10808" make build
```

该值只决定尚未保存设置时的首次选项，不会覆盖用户之后选择的“不干预”或“强制直连”。

长期使用时可复制 `Config/Local.make.example` 为 `Config/Local.make` 并填写本机默认值。该文件已被 Git 忽略，不会提交到仓库；CI 和其他人的全新克隆默认“不干预”。

从终端启动时，也可以用 `DSH_DESKTOP_PROXY_URL` 临时覆盖构建值：

```bash
DSH_DESKTOP_PROXY_URL="http://127.0.0.1:10808" build/DSH.app/Contents/MacOS/DSH
```

代理只用于 DSH 的外部请求；`127.0.0.1`、`localhost` 和 `::1` 始终绕过代理。

## 自动更新

1.2.0 起内置 Sparkle 2，并从 GitHub Releases 的 `appcast.xml` 检查更新。更新归档使用 Ed25519 签名验证；正式分发版本还应使用 Developer ID 签名并通过 Apple 公证。

从不含 Sparkle 的 1.1.0 升级到 1.2.0 时，需要手动覆盖安装一次。之后可从“DSH → 检查更新…”获取新版本。

本地准备 Release 资源的顺序如下：

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make dmg
NOTARY_KEYCHAIN_PROFILE="dsh-notary" make notarize
make appcast
```

`make appcast` 会把 DMG 和签名后的 `appcast.xml` 放入 `build/release/`。默认使用登录钥匙串中账号为 `BaronCyrus/dsh-desktop` 的 Sparkle 密钥，也可在 CI 中通过 `SPARKLE_PRIVATE_KEY` 提供私钥。

推送与应用版本一致的标签（例如 `v1.2.0`）会运行 Release 工作流。仓库需配置：

- `MACOS_CERTIFICATE_BASE64`、`MACOS_CERTIFICATE_PASSWORD`、`APPLE_SIGNING_IDENTITY`
- `APPLE_API_KEY_ID`、`APPLE_API_ISSUER_ID`、`APPLE_API_PRIVATE_KEY`
- `SPARKLE_PRIVATE_KEY`

工作流会构建通用应用、签名 DMG、完成 Apple 公证、生成 appcast，并发布 GitHub Release。

## 生成安装包

本地测试版使用临时签名：

```bash
make dmg
```

产物位于 `build/DSH-<版本>.dmg`。若要让其他用户正常下载安装，需要 Apple Developer Program 的 Developer ID 筿名和 Apple 公证：

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make dmg
NOTARY_KEYCHAIN_PROFILE="dsh-notary" make notarize
```

先用 `xcrun notarytool store-credentials dsh-notary` 将凭据保存在系统钥匙串中，不要把证书密码或 App Store Connect 密钥提交到仓库。

构建参数：

| 参数 | 默认值 | 用途 |
| --- | --- | --- |
| `APP_VERSION` | `1.2.0` | 对外版本号 |
| `BUILD_NUMBER` | `4` | 内部构建号 |
| `BUNDLE_ID` | `io.github.baroncyrus.dsh-desktop` | 应用标识 |
| `ARCHITECTURES` | `arm64 x86_64` | 目标架构 |
| `DEFAULT_PROXY_URL` | 空 | 可选的内置代理地址 |
| `CODE_SIGN_IDENTITY` | `-` | 临时签名或 Developer ID |

`BUNDLE_ID` 是 WebKit Cookie、系统权限和未来自动更新的身份依据。正式发布后应保持不变。

## 项目结构

```text
Sources/DSHDesktopApp/    AppKit + WebKit 界面和进程生命周期
Sources/DSHDesktopCore/   可测试的 token 解析与运行环境配置
Checks/                   不依赖测试框架的核心逻辑检查
Assets/                   图标源文件
Config/                   应用 Info.plist 模板
Tools/                    矢量图标生成工具
ReleaseNotes/             各版本更新说明
scripts/                  构建、验证、DMG 与公证脚本
```

## 路线图

- Windows 原生启动器
- 统一的跨平台网络与 DSH 进程配置

## 许可证与第三方材料

第三方声明见 `THIRD_PARTY_NOTICES.md`。`ThirdParty/` 中保留了上游 DSH 与 Sparkle 的许可证文本。

本项目原创代码采用 MIT License，详见 `LICENSE`。第三方材料仍分别遵循其原始许可证；MIT 软件许可证本身不授予商标权。
