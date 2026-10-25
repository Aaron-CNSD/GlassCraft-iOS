# GlassCraft macOS 0.2 开发预览

这是本项目新增的 SwiftUI 原生 Mac 应用，不是 Amethyst IPA 的改名包。源码位于 macos/，沿用本仓库 GPL-3.0 许可。

## 安装

下载 GlassCraft-macOS-universal.zip，解压后将 GlassCraft.app 放入应用程序。支持 macOS 13+，含 Apple Silicon 与 Intel 二进制。应用为临时签名，未经过 Apple 公证；系统可能阻止打开，可在系统设置「隐私与安全性」中按系统提示处理。无需关闭 Gatekeeper。

## 使用

1. 输入 3–16 位本地用户名，选择游戏版本与内存。
2. 点击「下载并启动游戏」：自动准备 Temurin Java、游戏文件、依赖库和音效资源；校验 SHA-256 / SHA-1。首次下载较大，请保持联网。
3. 游戏输出在 ~/Library/Application Support/GlassCraft/logs/latest.log；各版本有独立 instances 目录。
4. 「资源中心」打开网页检索；导入模组 / 光影只是复制文件。**自动安装 Forge/Fabric、整合包和启用光影尚未实现，当前自动启动仅支持原版 1.19+**。

本地账号不登录 Microsoft，不能进入要求正版验证的服务器。旧游戏版本的原生依赖未必兼容 Apple Silicon。没有物理 Intel Mac 或完整游戏进入世界的验证结果，不保证所有列出的版本能运行。未打包 Microsoft 游戏文件或 Java 二进制，首次启动从官方源获取。

## 开发

运行 `bash macos/build.sh`。下载接口为 Mojang manifest/resources 与 Adoptium v3；开源运行时的许可由其下载包保留。此版本未实现下载取消、Microsoft 登录或自动更新。

## 0.3：导入整合包

点击「导入整合包 .mrpack」，选择从 Modrinth 导出的文件，等待下载校验完成；在「启动配置」中选择该包，点击「下载并启动游戏」。导入后会自动选中整合包和对应游戏版本。可在运行游戏前更改用户名与内存；若用户名被禁用，先切回原版修改再选回整合包。

支持 Minecraft 1.19+ 的原版、Fabric、Quilt `.mrpack`，自动获取对应加载器配置和依赖。包内 overrides 与 client-overrides 按顺序覆盖，客户端标记为 optional / unsupported 的文件默认跳过。失败导入不会登记启动配置；每次导入创建新实例，不覆盖旧存档。

不支持 Forge、NeoForge、CurseForge ZIP。下载地址限 Modrinth / GitHub / GitLab 官方格式允许的主机；使用其他源的包会报告失败。导入与加载器依赖下载经过自动化测试，尚未完成游戏进入世界的真机验证。

## 0.4：选择加载器

在「启动配置」选择「新建 / 原版」，选择 Minecraft 版本，再在「加载器」中选择原版、Forge、NeoForge、Fabric 或 Quilt。选择对应的加载器版本后点击「安装加载器」。完成后会创建并自动选中独立配置，再点击「下载并启动游戏」。原版无需安装加载器。

Forge / NeoForge 从官方 Maven 下载并校验官方安装器，运行客户端安装流程以生成补丁与启动配置。Fabric / Quilt 使用官方 metadata 服务。Minecraft 版本范围仍为 1.19+；没有对应发行版时会提示。NeoForge 1.20.1 暂不提供，1.20.2+ 按对应版本筛选。

`.mrpack` 的 Forge / NeoForge 依赖现在也会调用相同安装流程。CurseForge ZIP 仍未适配。所有加载器安装均可能因上游网络或不兼容的处理器失败，错误信息会指向 logs/installer-Forge.log 或 installer-NeoForge.log。完整游戏进入世界仍未验证，不保证任意整合包都可运行。
