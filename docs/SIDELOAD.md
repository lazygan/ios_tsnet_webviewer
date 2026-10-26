# 免费 Apple ID 侧载说明

本项目产出的 IPA 不签名，需要在 Windows 上用 AltStore 或 Sideloadly 以免费 Apple ID 签名安装。

## 前置条件

- iPhone 已开启开发者模式：设置 → 隐私与安全性 → 开发者模式 → 重启并在开机后确认。
- 一个免费 Apple ID（建议使用专门的测试账号）。
- Windows 上安装 iTunes 和 iCloud（AltStore 要求使用 Apple 官网版本，不要用 Microsoft Store 版）。

## 方案一：Sideloadly（USB，手动）

1. 安装 Sideloadly 和 Apple 设备驱动（iTunes）。
2. 连接 iPhone，信任电脑。
3. 拖入 `TailBrowser-unsigned-<sha>.ipa`，输入 Apple ID。
4. 点击 Start，输入 Apple ID 密码/双重认证。
5. 安装完成后，若提示不受信任：设置 → 通用 → VPN 与设备管理 → 信任开发者证书。
6. 每 7 天重新执行一次（覆盖安装，数据保留）。

## 方案二：AltStore（同 Wi-Fi，可自动续签）

1. Windows 安装 AltServer。
2. 手机安装 AltStore（通过 AltServer 菜单）。
3. 用 AltServer 将 IPA 安装到设备。
4. 保持 AltServer 在同一网络运行，可在过期前自动续签。
5. 同样需要在设置中信任开发者证书。

## 免费账号限制

- 证书 7 天有效。
- 每台设备最多 3 个侧载 App。
- 每周最多 10 个 App ID。
- 无法使用 App Groups、Network Extension、Push 等需要额外权限的能力（本项目不需要）。
- 覆盖安装不会丢失 App 数据；**不要卸载 App**，卸载会清空 tsnet 身份和书签。

## 排错

- 安装失败「Unable to install」：确认开发者模式已开启、设备已信任电脑、IPA 架构为 arm64。
- 启动闪退：优先检查是否内嵌了动态框架且未被重签（`docs/PHASE0.md` P0.1 记录产物类型）。
- 证书过期：重新签名覆盖安装；若仍不可用，删除证书后重装（会丢数据，先导出诊断）。
