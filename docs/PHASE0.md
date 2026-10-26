# Phase 0 验证清单

目标：在铺开 UI 之前，用最小闭环验证四个高风险点。每一项记录实测结果，全部通过后再进入里程碑 M2。

## 验证项

- [ ] **P0.1 gomobile + tsnet**
  - `bash scripts/build_go.sh` 成功生成 `ios/Frameworks/Tailbridge.xcframework`。
  - 记录 `file` 输出（静态 ar archive / 动态 dylib）、架构切片、体积、构建耗时。
- [ ] **P0.2 CI 出包**
  - GitHub Actions `ios-unsigned` 绿。
  - artifact 中包含可用的无签名 `.ipa` 和构建日志。
  - `scripts/verify_ipa.sh` 通过（bundle ID、MinimumOSVersion、ATS、arm64）。
- [ ] **P0.3 免费账号侧载**
  - Windows 上用 AltStore 或 Sideloadly 安装并启动。
  - 记录 Developer Mode、证书信任、重签流程。
  - 重签覆盖安装后数据不丢。
- [ ] **P0.4 tsnet 生命周期**
  - 粘贴一次性 Auth Key，`BackendState` 达到 `Running`。
  - 节点出现在 Tailscale 管理后台，peer 列表非空。
  - 杀进程重开无需重新登录。
  - 日志中无 `os.Executable` 相关错误。
- [ ] **P0.5 SOCKS5 + tsnet.Dial**
  - App 内自测（或宿主机 `curl --socks5`）经代理访问 peer 的 HTTP 服务成功。
  - 非 tailnet 目标被拒绝。
  - Stop 后活动连接全部关闭。
- [ ] **P0.6 WKWebView 代理**
  - `WKWebsiteDataStore(forIdentifier:)` + `ProxyConfiguration(socksv5Proxy:)` 生效。
  - tailnet HTTP 页面正常加载。
  - 停止代理/tsnet 后页面加载失败，不会绕过代理直连。
- [ ] **P0.7 WebKit 行为记录**
  - SOCKS 请求使用 `ATYP=domain` 还是本地解析后的 IP。
  - HTTP `Host` 头是否保留。
  - IP URL 与 MagicDNS 名称 URL 的差异。
- [ ] **P0.8 诊断导出**
  - 导出的诊断文件包含版本、状态、日志、自测结果。
  - 不包含 Auth Key 或任何密钥材料。

## 必须核实的 API（以 macOS SDK 为准）

- `WKWebsiteDataStore.proxyConfigurations`
- `WKWebsiteDataStore(forIdentifier:)`
- `Network.ProxyConfiguration(socksv5Proxy:)`
- `ProxyConfiguration.allowFailover`
- `ProxyConfiguration.applyCredential(username:password:)`

运行 `bash scripts/check_sdk_headers.sh` 记录实际声明。

## 结论记录

| 项目 | 结果 | 备注 |
|---|---|---|
| gomobile 产物类型 | 待测 | gomobile 源码显示为静态库（lipo 合并 `.a`）；待 CI `file` 输出确认 |
| 代理 API 可用性 | 待测 | 由 CI 的 `check_sdk_headers.sh` 记录 |
| tsnet 版本 | v1.104.1 | 已在本地 module cache 确认包含 iOS `os.Executable` 回退；待真机验证 |
| 首次构建耗时 | 待测 | |
| 缓存后构建耗时 | 待测 | |
| IPA 体积 | 待测 | |
| 测试 iOS 版本 | 待测 | |
