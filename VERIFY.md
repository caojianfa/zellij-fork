# OSC 9 / OSC 777 透传 — 验证指南

这份文档提供了在你本地机器上验证 patch 行为的步骤。涵盖功能验证 + 配置开关 + stacked pane 视觉指示 + OSC 99 回归测试。

## 0. 准备

下载 GitHub Release 里附带的二进制：

- 文件名：`zellij`（Linux x86_64 musl 静态二进制）
- 下载后放到任意目录，例如：`~/Downloads/zellij`
- 加可执行权限：

```bash
chmod +x ~/Downloads/zellij
```

> 注：这是一个 release-mode 静态构建（musl target），不依赖系统 glibc 版本。下面所有命令里的 `./zellij` 替换成你的实际路径即可。

> ⚠️ 验证需要在一个**支持桌面通知 OSC 序列**的宿主终端里跑。已知工作良好的：
> - **iTerm2**（OSC 9 原生支持）
> - **kitty**（OSC 777 原生支持，OSC 9 也支持）
> - **WezTerm**（OSC 9 / 777 都支持）
> - **Alacritty**（OSC 777 支持）
> - **Ghostty 1.3.1+**（OSC 9 / 777 都支持，未来版本会加 OSC 99）
>
> 你说的环境是 ghostty，下面的步骤都基于 ghostty 写。

## 1. Baseline — 验证宿主终端通知本身工作（不开 zellij）

先确认你的 ghostty 能弹通知：

```bash
sleep 3; printf '\e]9;baseline notification from ghostty\a'
```

切走焦点 3 秒，应该看到一条系统通知，标题是 ghostty 的默认应用名（macOS 通知中心 / Linux dunst 等），内容是 `baseline notification from ghostty`。

**预期结果**：
- ✅ 弹出一条系统通知，内容含 "baseline notification from ghostty"
- ❌ 如果没有通知 → 检查 ghostty 通知权限（macOS 系统设置 → 通知 → ghostty 打开；Linux 检查 dunst/通知守护进程在跑）

如果 baseline 失败，下面的 zellij 测试都不可能成功，先把宿主终端通知调通。

## 2. 默认配置下：OSC 9 透传

启动 patch 后的 zellij：

```bash
./zellij
```

进入 zellij 后，在任意 pane 里跑：

```bash
sleep 3; printf '\e]9;test from zellij\a'
```

切走 ghostty 焦点 3 秒。

**预期结果**：
- ✅ 弹出一条系统通知，内容含 "test from zellij"
- ✅ pane 边框闪烁一下（visual bell）
- ✅ 如果当前 tab 不是焦点，tab 标题栏出现 `[!]` 标记

## 3. OSC 777 — 带标题的通知

在 zellij 里跑：

```bash
sleep 3; printf '\e]777;notify;Build Done;All tests passed\a'
```

**预期结果**：
- ✅ 弹出系统通知：标题 = "Build Done"，正文 = "All tests passed"
- ✅ 同样有视觉指示

## 4. 关闭 passthrough — 只视觉指示，不透传

编辑 zellij 配置文件：

```bash
mkdir -p ~/.config/zellij
$EDITOR ~/.config/zellij/config.kdl
```

在文件末尾追加（如果文件不存在，直接新建并写入）：

```kdl
allow_osc_passthrough false
```

退出 zellij（`Ctrl+q` 或者 detach `Ctrl+o d`），然后重新启动：

```bash
./zellij
```

> 如果你想在 KDL 配置写注释方便之后改回来，可以这样写：
> ```kdl
> // 关掉 OSC 9/777 桌面通知透传，仅触发 zellij 内部视觉指示
> allow_osc_passthrough false
> ```

跑同样的 OSC 9 测试：

```bash
sleep 3; printf '\e]9;should NOT pop up a notification\a'
```

**预期结果**：
- ❌ 没有系统通知（被 zellij 拦截了）
- ✅ pane 边框仍然闪烁
- ✅ tab 仍然有 `[!]` 标记
- 即：用户能在 zellij 内看到"有事发生了"，但宿主桌面不会被打扰

验证完之后，把 KDL 里的那行改回来或删掉，恢复默认行为：

```kdl
allow_osc_passthrough true
```

## 5. Stacked panes — 折叠子 pane 的视觉指示

zellij 的 stacked pane 模式下，非焦点的子 pane 会被折叠成一行。验证 OSC 9 在折叠子 pane 里也能触发标题栏视觉指示。

步骤：

1. 在 zellij 里按 `Ctrl+p` 进入 PANE 模式，再按 `n` 创建一个新 pane
2. 再创建一个，让你有 3 个 pane
3. 按 `s` 切换为 stacked 布局
4. 选中**非焦点的某个折叠子 pane**（用方向键导航到一个折叠行）
5. 在那个折叠子 pane 里跑：

```bash
sleep 5; printf '\e]9;notification from folded pane\a'
```

6. 立刻按方向键切到**另一个 pane**让源 pane 变折叠+不焦点
7. 等 5 秒

**预期结果**：
- ✅ 弹出系统通知 "notification from folded pane"
- ✅ 折叠子 pane 的标题栏显示 `[!]` 视觉指示（即使它折叠成一行）
- ✅ 当前 tab 标题加 `[!]`

## 6. 回归测试：OSC 99 必须仍然工作

PR #4931 上游引入的 OSC 99 透传不能被我们的 patch 破坏。在 zellij 里跑：

```bash
printf '\e]99;i=test1:p=title;OSC 99 still works\e\\'
```

**预期结果**：
- ⚠️ ghostty 1.3.1 暂时不响应 OSC 99（spec 还在落地中），所以**不会**弹通知，这是预期行为
- ✅ 关键观察点：zellij 应该正确把字节透传出去（不会卡住、报错或丢字符）
- ✅ 不抛异常，不影响后续输入

如果你有 iTerm2 或者 kitty 这种已经支持 OSC 99 的终端，可以用同样的命令验证它会弹通知。

## 7. CLI flag 测试（可选）

新加的配置项也支持命令行覆盖：

```bash
./zellij --allow-osc-passthrough false
```

进入后跑 OSC 9，应该和第 4 节一样不弹通知。

## 8. 验证 BEL 终止符 vs ST 终止符

OSC 序列有两种终止符。验证两种都能透传：

**BEL 终止符（`\a` = `\x07`）**：
```bash
printf '\e]9;BEL terminated\a'
```

**ST 终止符（`\e\\` = `ESC \`）**：
```bash
printf '\e]9;ST terminated\e\\'
```

**预期结果**：两条都应该弹通知（patch 实现了对两种终止符的对称处理）。

## 9. 异常输入鲁棒性（可选 sanity check）

确认我们的 patch 不会在异常输入时崩溃：

```bash
# OSC 9 空 body
printf '\e]9;\a'

# OSC 777 没有 notify 子命令（patch 应该静默忽略）
printf '\e]777;Beep\a'

# OSC 777 只有 title 没有 body
printf '\e]777;notify;OnlyTitle;\a'
```

**预期结果**：
- 第 1 个：无通知（body 空），pane 边框可能闪烁（因为 OSC 9 触发 visual bell）
- 第 2 个：无通知，无视觉指示（非 notify 子命令，patch 没把它当通知处理）
- 第 3 个：弹通知，标题 "OnlyTitle"，body 为空（这个由宿主终端决定怎么显示）
- 全程 zellij 不卡死、不报错

---

## 出问题怎么办？

1. **没收到任何通知**：先跑第 1 节 baseline。如果 baseline 都失败 → 是宿主终端 / 系统通知权限问题，和 zellij patch 无关。
2. **baseline 通过但 zellij 里不弹**：检查是不是配置文件里有 `allow_osc_passthrough false`。
3. **OSC 99 也不工作**：那就是 patch 把上游逻辑搞坏了，请反馈。
4. **崩溃 / panic**：把堆栈贴回来给我。
5. **KDL 解析报错**（启动 zellij 时报 unknown option 之类）：说明 patch 编译版本和你的 KDL 配置文件不匹配，确认你跑的是 release 里下载的 binary 而不是 PATH 上的旧 zellij。

---

## 期望覆盖矩阵

| 测试场景 | 系统通知 | 视觉指示 |
| --- | :---: | :---: |
| § 2 默认 OSC 9 | ✅ | ✅ |
| § 3 默认 OSC 777 (notify) | ✅ | ✅ |
| § 4 关闭 passthrough + OSC 9 | ❌ | ✅ |
| § 5 stacked pane 折叠子 pane OSC 9 | ✅ | ✅ |
| § 6 OSC 99 ghostty 不响应 | ❌ (terminal 不支持) | — |
| § 8 OSC 9 BEL/ST 终止符 | ✅ | ✅ |
| § 9 OSC 9 空 body | ❌ | ✅ |
| § 9 OSC 777 非 notify | ❌ | ❌ |
