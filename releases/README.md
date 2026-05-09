# 下载安装包

这个目录提供 patch 后的 zellij 二进制，用来手动验证 OSC 9 / OSC 777 桌面通知透传。

## 文件清单

| 文件 | 大小 | 平台 |
| --- | --- | --- |
| `zellij-osc-9-777-macos-aarch64-apple-silicon.tar.gz` | 15 MB | **macOS Apple Silicon** (M1/M2/M3+) |
| `zellij-osc-9-777-macos-x86_64-intel.tar.gz` | 15 MB | **macOS Intel** |
| `zellij-osc-9-777-linux-x86_64-musl.tar.gz` | 18 MB | **Linux x86_64** (musl 静态) |
| `SHA256SUMS` | 548 B | 全部文件的 SHA256 校验和 |

## 推荐：用 Homebrew 装（macOS）

仓库根目录有现成的 Formula。**先下载到本地，再装**（modern brew 不支持直接从 URL 装 `.rb` formula）：

```bash
# 1. 卸载官方 zellij
brew uninstall zellij

# 2. 下载我们的 formula 到本地
curl -fsSL -o /tmp/zellij-osc-patch.rb \
  https://raw.githubusercontent.com/Caojianfa/zellij-fork/claude/osc-notification-passthrough-WMI63/Formula/zellij-osc-patch.rb

# 3. 装
brew install --formula /tmp/zellij-osc-patch.rb
```

formula 自动选 Apple Silicon 还是 Intel binary，全自动校验 SHA256。装出来在 brew 里登记的名字是 `zellij-osc-patch`，但**实际可执行文件叫 `zellij`**，会覆盖你 PATH 里原来的那个，所以直接 `zellij` 就是 patch 版本。

**测完恢复官方 zellij：**

```bash
brew uninstall zellij-osc-patch && brew install zellij
```

如果你测试中改过 `~/.config/zellij/config.kdl`（比如加了 `allow_osc_passthrough false`），记得**先把那行删掉再跑** `brew install zellij`，不然旧版本会因为不认识这个新 KDL 字段拒绝启动。

## 替代方案：直接下载二进制

### macOS Apple Silicon（M1/M2/M3+）

```bash
curl -LO https://github.com/Caojianfa/zellij-fork/raw/claude/osc-notification-passthrough-WMI63/releases/zellij-osc-9-777-macos-aarch64-apple-silicon.tar.gz
tar xzf zellij-osc-9-777-macos-aarch64-apple-silicon.tar.gz
chmod +x zellij-osc-9-777-macos-aarch64-apple-silicon
./zellij-osc-9-777-macos-aarch64-apple-silicon  # 直接运行，或 mv 到 PATH
```

> macOS 第一次跑会被 Gatekeeper 拦（因为没有签名）。绕过办法：
> ```bash
> xattr -d com.apple.quarantine zellij-osc-9-777-macos-aarch64-apple-silicon
> ```
> 然后再运行。

### macOS Intel

```bash
curl -LO https://github.com/Caojianfa/zellij-fork/raw/claude/osc-notification-passthrough-WMI63/releases/zellij-osc-9-777-macos-x86_64-intel.tar.gz
tar xzf zellij-osc-9-777-macos-x86_64-intel.tar.gz
chmod +x zellij-osc-9-777-macos-x86_64-intel
xattr -d com.apple.quarantine zellij-osc-9-777-macos-x86_64-intel  # 绕过 Gatekeeper
./zellij-osc-9-777-macos-x86_64-intel
```

### Linux x86_64

```bash
curl -LO https://github.com/Caojianfa/zellij-fork/raw/claude/osc-notification-passthrough-WMI63/releases/zellij-osc-9-777-linux-x86_64-musl.tar.gz
tar xzf zellij-osc-9-777-linux-x86_64-musl.tar.gz
chmod +x zellij-osc-9-777-linux-x86_64-musl
./zellij-osc-9-777-linux-x86_64-musl
```

## 校验

```bash
curl -LO https://github.com/Caojianfa/zellij-fork/raw/claude/osc-notification-passthrough-WMI63/releases/SHA256SUMS
shasum -a 256 -c SHA256SUMS  # macOS
sha256sum -c SHA256SUMS       # Linux
```

应该全部 `OK`。

## 验证步骤

照仓库根目录的 [`VERIFY.md`](https://github.com/Caojianfa/zellij-fork/blob/claude/osc-notification-passthrough-WMI63/VERIFY.md) 跑 9 个场景。最关键的就 3 个：

1. **OSC 9 默认透传**：进入 zellij 后 `sleep 3; printf '\e]9;test from zellij\a'` → 弹通知 + pane 边框闪烁
2. **OSC 777 带标题**：`sleep 3; printf '\e]777;notify;Build Done;All tests passed\a'` → 弹带标题的通知
3. **关闭 passthrough**：在 `~/.config/zellij/config.kdl` 加一行 `allow_osc_passthrough false`，重启 zellij 再跑 OSC 9，应该**只有视觉指示，没有系统通知**

## 完全卸载

```bash
# 如果用了 Homebrew
brew uninstall zellij
brew install zellij  # 装回官方版本

# 删除测试时加的 KDL 配置（如果加过）
$EDITOR ~/.config/zellij/config.kdl
# 删掉 allow_osc_passthrough false 那行

# 直接下载方案下，删除二进制
rm zellij-osc-9-777-* SHA256SUMS
```
