# GlassCraft — iOS / macOS

macOS 0.4 原生开发预览（原版 / Forge / NeoForge / Fabric / Quilt 选择与安装）：源码在 `macos/`，安装与限制见 [docs/MACOS.md](docs/MACOS.md)。iOS 分支仍未产出自己的可安装 IPA。

# GlassCraft iOS — 开发预览

基于 [AngelAuraMC/Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) 的 Minecraft Java Edition iOS 启动器分支，保留 GPL-3.0 许可、原作者版权与历史。原始说明见 README.upstream.md。非 Mojang / Microsoft 官方产品。

官网与资源中心：https://aarongame.com/glasscraft/

## 功能与状态

- 沿用上游原生引擎：游戏版本下载、Microsoft 登录、游戏启动、Java 运行时管理、模组与 Modrinth 整合包安装。
- 新增 GlassCraft 显示名称、网页版模组 / 整合包 / 光影资源检索、版本清单与资源 API。
- 光影在资源中心检索下载后需手动放入游戏目录 shaderpacks，并安装匹配的 Iris / OptiFine。并非所有光影、模组或整合包适用于 iOS 渲染器。
- Java 必须是兼容 iOS 的运行时；不得用桌面 JDK 安装包替代。运行时下载/选择使用上游管理功能，并受运行时服务可用性影响。
- 当前分支尚未完成原生构建和 iPhone 真机测试，**没有可验证的 GlassCraft IPA**。官网的下载入口是源码，不是安装包。勿把本版本当成已发布的可安装应用。

## 安装与使用

1. 使用具备 Java 版授权的 Microsoft 账号。不要把账号密码交给资源 API。
2. 阅读[上游安装说明](https://wiki.angelauramc.dev/wiki/getting_started/INSTALL)，核对你的 iOS 与 JIT 支持情况。网页本身不能运行 Java 版游戏。
3. 目前可使用上游正式发行版体验引擎；本分支需由开发者按上游构建步骤编译并用自己的证书侧载。不要直接把上游 IPA 当作 GlassCraft 安装包。
4. 在原生启动器中登录、选择游戏版本和适配运行时，再下载启动。先验证原版，再安装匹配游戏版本与加载器的模组。
5. 整合包使用启动器内的 Modrinth 安装入口；资源中心下载的 jar / zip 需按上游文件管理方式导入。光影需手动启用，复杂效果可能无法运行。

## 开发与 API

保留上游 Makefile、Xcode 工程与构建依赖。先阅读上游说明并准备对应 iOS JRE、原生依赖与签名环境。上游 CI 依赖专用自托管 runner，本分支不保证 GitHub Actions 能自动出包。

API 文档见 docs/API.md；服务实现见 service/。API 仅公开资源元数据，不提供微软登录代理、盗版验证或远程启动 iPhone。

教程视频是带中文字幕的安装流程说明，不是 GlassCraft 真机运行录像。Bilibili 发布文案见 docs/BILIBILI.md。
