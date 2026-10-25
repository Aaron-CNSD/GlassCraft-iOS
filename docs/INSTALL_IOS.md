# iPhone / iPad 原生安装入口

现阶段提供上游官方已编译开发构建，**不是本分支自行编译的 GlassCraft IPA**。

下载：https://nightly.link/AngelAuraMC/Amethyst-iOS/workflows/development/main/org.angelauramc.amethyst-ios.ipa.zip
官方安装文档：https://wiki.angelauramc.dev/wiki/getting_started/INSTALL

1. 下载 ZIP 并解压出 IPA。
2. 按官方文档通过兼容的 SideStore / AltStore / TrollStore 侧载，准备 JIT 与所需内存权限。普通未越狱设备通常涉及电脑辅助；具体方案依 iOS 版本而定。
3. 原生账号列表 → 添加 → Local Account（本地账号）→ 输入 3–16 位用户名。上游原生已有该功能，不需要 Microsoft 登录。无法进入要求正版验证的服务器。
4. 选择游戏版本和兼容的 iOS Java 运行时，启动原版测试；再安装模组和整合包，光影仍需匹配渲染器。

上游基础设备支持从 iOS 14 开始，但不保证每个后续 iOS 版本都能启用 JIT。不能承诺“大多数设备开箱即用”。本次尚无实机测试结果。
