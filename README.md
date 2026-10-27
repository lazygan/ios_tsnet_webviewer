# TailWeb

iOS 上的 Tailscale 浏览器：在 App 进程内运行用户态 Tailscale 节点（`tsnet`），通过本地 SOCKS5 代理驱动 `WKWebView`，访问 tailnet 内部的 HTTP 服务。

当前状态：**Phase 0**。核心链路已实现，CI 出包与免费账号侧载已打通（iPASide）；真机冒烟测试进行中，见 `docs/PHASE0.md`。

## 架构

```
WKWebView
  │  经 WKWebsiteDataStore.proxyConfigurations 指向
  ▼
127.0.0.1:<port>  SOCKS5（Go，进程内）
  │  tsnet.Dial
  ▼
tsnet（用户态 WireGuard 节点）
  │
  ▼
tailnet 机器 http://100.x.y.z:<port>
```

- 不创建 VPN 配置，不使用 Network Extension，不需要 Apple entitlement。
- 只代理本 App 的 WebView 流量；App 退到后台后隧道挂起。
- MVP 仅允许访问 tailnet 地址（`100.64.0.0/10`、`fd7a:115c:a1e0::/48` 和 Status 中已知的 peer 主机名）。

## 仓库结构

```
go/                 Go module（tsnet 封装、SOCKS5、日志）
ios/                SwiftUI App 源码 + XcodeGen 配置
scripts/            构建、打包、校验脚本
.github/workflows/  macOS CI：生成 XCFramework + 无签名 IPA
docs/               Phase 0 清单、工具链、侧载说明
```

## 构建

开发机为 Windows，iOS 构建全部在 GitHub Actions 的 macOS runner 上完成：

1. 推送代码或在 Actions 中手动触发 `ios-unsigned`。
2. 下载 artifact `TailBrowser-unsigned-<sha>.ipa`。
3. 用 iPASide（推荐，Sideloadly 当前受 Apple `-80046` 限制）配合免费 Apple ID 签名安装，详见 `docs/SIDELOAD.md`。

Go 部分可以在 Windows 本地验证：

```bash
cd go
go vet ./...
go test ./...
```

## 配置

- 在 Tailscale 管理后台生成 Auth Key（建议带 tag、设置过期时间），首次启动时粘贴到 App 内。
- Auth Key 保存在 iOS Keychain，仅用于首次节点注册；之后节点身份持久化在 Application Support。
- 设备名和 Control URL（默认官方云）可在设置中修改。

## 已知限制

- 仅前台可用；退到后台后连接中断。
- 仅访问 tailnet，页面中的外网资源（CDN、字体、第三方 API）不会加载。
- WKWebView 无法跳过自签 HTTPS 证书校验；内网服务请使用 HTTP 或在设备上安装内部 CA。
- 免费 Apple ID 签名 7 天过期，需要定期重签。
- 不使用 Headscale（保留 Control URL 输入，但未验证）。
