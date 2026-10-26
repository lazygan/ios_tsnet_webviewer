# 工具链与版本锁定

CI 中的版本必须固定并记录在这里。Phase 0 完成后，把占位项替换为实测通过的版本。

## 当前配置

| 组件 | 版本 | 位置 |
|---|---|---|
| Go | 1.27.3（本地验证；`go.mod` 语言版本 1.27.1） | `.github/workflows/ios.yml` 的 `GO_VERSION` |
| tailscale.com | v1.104.1（已含 iOS `os.Executable` 修复） | `go/go.mod` |
| gomobile / gobind | `v0.0.0-20261011034528-197770444867` | `.github/workflows/ios.yml` 的 `GOMOBILE_VERSION` |
| Xcode | runner 默认（macos-15），Phase 0 后固定 | `.github/workflows/ios.yml` |
| XcodeGen | Homebrew 最新，Phase 0 后固定 | `.github/workflows/ios.yml` |
| 部署目标 | iOS 17.0 | `ios/project.yml` |

## 记录命令

每次 CI 构建都会执行，产物 `build-toolchain.txt` 随 artifact 上传：

```bash
go version
cd go && go list -m tailscale.com
go version -m "$(which gomobile)" | head -n 5
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
xcodegen --version
file ios/Frameworks/Tailbridge.xcframework/ios-arm64/Tailbridge.framework/Tailbridge
```

## 注意事项

- `gomobile bind` 必须与构建它的 Go 版本匹配；升级 Go 时一起验证。
- `tailscale.com` v1.104.1 已验证包含 iOS 可执行路径回退（`tsnet.go` 中 darwin/ios 分支使用 `os.Executable` 失败后的兜底路径）。复核命令：

  ```bash
  grep -n "Executable" "$(go env GOMODCACHE)"/tailscale.com@v1.104.1/tsnet/tsnet.go
  ```

- gomobile 在本工程的 iOS 目标上产出**静态库**（`.a` + 头文件/Swift module）。因此 Xcode 工程使用 `embed: false`；若某次实测变为动态库，改为 `embed: true` 并验证免费账号重签。
- `check_sdk_headers.sh` 的输出会写入 CI 日志，用于确认目标 SDK 上 `WKWebsiteDataStore.proxyConfigurations` 与 `Network.ProxyConfiguration` 的实际声明。
