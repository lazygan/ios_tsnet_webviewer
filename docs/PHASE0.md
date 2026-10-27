# Phase 0 验证清单

目标：在铺开 UI 之前，用最小闭环验证四个高风险点。每一项记录实测结果，全部通过后再进入里程碑 M2。

状态（2026-10-27）：P0.1、P0.2 已通过；P0.3 已用 iPASide 1.2.12 完成首次签名安装，待确认启动与覆盖安装；P0.4–P0.8 待真机实测。

## 验证项

- [x] **P0.1 gomobile + tsnet**
  - CI 中 `bash scripts/build_go.sh` 成功生成 `ios/Frameworks/Tailbridge.xcframework`（run 40343280538，XCFramework 首次构建 2m04s）。
  - `file` 输出（run 40343280538）：
    - device 切片：`Mach-O universal binary with 1 architecture: [arm64:current ar archive random library]`
    - simulator 切片：`Mach-O universal binary with 2 architectures: [x86_64:current ar archive random library] [arm64]`
  - 结论：gomobile 产出**静态库**（ar archive），Xcode 工程使用 `embed: false`。
  - XCFramework 缓存体积约 25 MB；缓存命中时该步骤跳过。
- [x] **P0.2 CI 出包**
  - GitHub Actions `ios-unsigned` 绿：run 40477141610（`ca8ee2e`）。
  - artifact 中包含 `TailBrowser-unsigned.ipa`、`build-xcodebuild.log`、`build-toolchain.txt`。
  - `scripts/verify_ipa.sh` 输出：`bundle id: com.example.tailweb`、`minimum OS: 17.0`、`ATS web content: true`、`Mach-O 64-bit executable arm64`、`embedded frameworks: none`。
- [ ] **P0.3 免费账号侧载**
  - [x] 已用 iPASide 1.2.12 签名安装 `ca8ee2e`（2026-10-27 19:58，证书到期 2026-11-03）。
  - [ ] 真机启动确认。
  - [ ] 重签覆盖安装后数据不丢。
  - 备注：Sideloadly 受 Apple 2026-10 的 `-80046` 登录限制影响，改用 iPASide；详见 `docs/SIDELOAD.md`。
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

已由 CI `scripts/check_sdk_headers.sh` 在 iPhoneOS18.5 SDK 上确认（run 40477141610）：

- `WKWebsiteDataStore.proxyConfigurations`：`@property (nullable, nonatomic, copy) NSArray<nw_proxy_config_t> *proxyConfigurations ... API_AVAILABLE(macos(14.0), ios(17.0))`
- `Network.ProxyConfiguration.allowFailover`：`public var allowFailover: Swift.Bool`
- `Network.ProxyConfiguration.applyCredential(username:password:)`
- `Network.ProxyConfiguration(socksv5Proxy:)`
- `WKWebsiteDataStore(forIdentifier:)` 与上述代理配置配合使用（iOS 17+）。

## 结论记录

| 项目 | 结果 | 备注 |
|---|---|---|
| gomobile 产物类型 | 静态 ar archive | device 仅 arm64；simulator 为 arm64+x86_64；Xcode `embed: false` |
| 代理 API 可用性 | 可用（iOS 17.0+） | SDK 18.5 头文件与 Swift interface 已确认 |
| tsnet 版本 | v1.104.1 | 已包含 iOS `os.Executable` 回退；真机日志待确认 |
| 首次构建耗时 | XCFramework 2m04s；workflow < 4min | run 40343280538，不含排队时间 |
| 缓存后构建耗时 | XCFramework 步骤跳过 | Xcode 主体构建约 2.5min |
| IPA 体积 | 8,056,932 B（约 7.7 MiB） | 解压后约 22.3 MB；SHA256 `9541ab5a13f861c0620ef4b0b01a54f3fe5c3b1264124b1eb4ac7d9b748f8034` |
| 测试 iOS 版本 | 待填 | 设备 UDID `00008120-000E2D190262201E`（iPASide 安装记录） |
