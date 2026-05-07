# 下载安装包

这个目录提供 patch 后的 zellij 二进制，用来手动验证 OSC 9 / OSC 777 桌面通知透传。

## 文件清单

| 文件 | 大小 | 说明 |
| --- | --- | --- |
| `zellij-osc-9-777-linux-x86_64-musl.tar.gz` | 18 MB | release 静态二进制（Linux x86_64，musl 静态链接，已 strip） |
| `SHA256SUMS` | 209 B | 解压前后两个文件的 SHA256 校验和 |

## 平台

- **Linux x86_64**：直接用，musl 静态链接，不依赖系统 glibc 版本，从 Ubuntu 20.04 到最新都能跑。
- **macOS**：本仓库目前不提供 macOS 二进制（构建环境是 Linux）。如果需要，自己 clone 仓库并 `cargo install --path . --release` 编译。
- **Windows**：zellij 主线本来就不官方支持 Windows，本 patch 也不例外。

## 下载步骤

### 浏览器下载

1. 打开 https://github.com/Caojianfa/zellij-fork/blob/claude/osc-notification-passthrough-WMI63/releases/zellij-osc-9-777-linux-x86_64-musl.tar.gz
2. 点页面右上的「Download raw file」按钮
3. 保存到本地任意位置

### 命令行下载（推荐）

```bash
curl -LO https://github.com/Caojianfa/zellij-fork/raw/claude/osc-notification-passthrough-WMI63/releases/zellij-osc-9-777-linux-x86_64-musl.tar.gz
curl -LO https://github.com/Caojianfa/zellij-fork/raw/claude/osc-notification-passthrough-WMI63/releases/SHA256SUMS
```

## 校验

```bash
sha256sum -c SHA256SUMS
```

应该看到：
```
zellij-osc-9-777-linux-x86_64-musl.tar.gz: OK
```

> 如果你解压前先校验，会少一行 `zellij-osc-9-777-linux-x86_64-musl: OK`，那是预期的（解压后的二进制还没出现）。

## 解压 + 安装

```bash
tar xzf zellij-osc-9-777-linux-x86_64-musl.tar.gz
chmod +x zellij-osc-9-777-linux-x86_64-musl
mv zellij-osc-9-777-linux-x86_64-musl /usr/local/bin/zellij-osc-test  # 或者放到任何 PATH 上的目录
```

> 注意：建议改名为 `zellij-osc-test` 之类，避免覆盖你系统里已有的 `zellij`。这样验证完直接 `rm /usr/local/bin/zellij-osc-test` 就清干净了。

## 启动

```bash
zellij-osc-test
```

或者不加到 PATH：

```bash
./zellij-osc-9-777-linux-x86_64-musl
```

## 验证步骤

打开 [`../VERIFY.md`](../VERIFY.md)，照里面 9 个场景跑就行。

## 卸载

```bash
rm /usr/local/bin/zellij-osc-test  # 或者你放二进制的位置
rm zellij-osc-9-777-linux-x86_64-musl.tar.gz SHA256SUMS
```

如果之前为了验证修改过 `~/.config/zellij/config.kdl`（添加了 `allow_osc_passthrough false`），记得改回来或删除。
