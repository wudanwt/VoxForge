# VoxForge / 声铸

VoxForge 声铸是一款面向 AI 编程的原生 macOS 全局语音输入增强器。它常驻菜单栏，用快捷键或 DJI Mic Mini 2 按钮启动听写，把口语锻造成可直接输入的编程提示词、消息或命令，并在需要时发送回车。

- 作者：super dan
- 版本：`1.0.0 (1)`
- 平台：macOS 14+，优先面向 Apple Silicon
- 副标题：VoxForge 声铸：面向 AI 编程的语音输入法
- 默认路线：本地语音识别优先，文本大模型优化可选

## 核心功能

- 全局听写：按一次开始，再按一次结束并输入，再按一次发送回车。
- 中文极速本地识别：默认使用 sherpa-onnx Streaming Paraformer bilingual zh-en。
- WhisperKit 备选：提供流式模式和兼容 batch 模式。
- 大模型优化：支持 OpenAI 兼容 `/v1/chat/completions`，API Key 存钥匙串。
- DJI Mic 触发器：原生监听 DJI Mic Mini 2 的 `volume_increment` 按钮事件，不再必须依赖 Karabiner。
- 悬浮 HUD：底部磨砂玻璃提示窗，显示听写、转写、优化、输入、完成和错误状态。
- 本地历史：可保存最终文本、原始转写、目标应用、耗时和是否大模型优化。

## 快速运行

```bash
./script/build_and_run.sh
```

脚本会执行 SwiftPM 构建、组装 `dist/VoxForge.app`、复制图标和 sherpa runtime、临时签名并启动应用。源码模块仍保留 `TypeMore` 名称，便于延续现有测试、模型缓存和历史数据。

Codex 的 Run 动作已经通过 `.codex/environments/environment.toml` 指向同一个脚本。

## 首次配置

1. 启动 VoxForge 声铸。
2. 在系统设置中允许麦克风权限。
3. 在系统设置的「隐私与安全性 > 辅助功能」中允许 VoxForge 声铸，用于粘贴文本和发送回车。
4. 如果启用 DJI 触发器并需要阻止系统音量变化，请同时允许相关输入监控/Event Tap 权限。
5. 如使用中文极速本地识别，先准备 sherpa runtime 和模型。

## 快捷键

- 听写快捷键：`Control + Option + D`
- 回车快捷键：`Control + Option + Return`
- 中断快捷键：`Control + Option + Esc`

听写快捷键复用三段状态机：

```text
第 1 次：开始听写
第 2 次：结束听写并输入文本
第 3 次：发送回车
```

中断快捷键用于取消当前听写、识别、润色、输入或等待发送流程。

关闭主窗口不会退出应用，VoxForge 声铸会继续留在菜单栏中。菜单栏入口可开始/中断听写、发送回车、切换模式、打开主窗口或进入设置。

## DJI Mic Mini 2 触发器

在「设置 > DJI 触发器」中启用。默认匹配：

```text
vendor_id: 11427
product_id: 16401
```

行为：

- 单击 DJI 按钮：执行当前主动作，即开始听写 / 完成输入 / 发送回车。
- 按住取消修饰键再按 DJI 按钮：中断当前流程。默认修饰键为 Ctrl，可改为 Option、Command 或 Shift。
- 默认尝试独占选中的 DJI HID 设备，阻止原始 `volume_increment`，避免系统音量升高。
- 如果独占失败，会降级尝试 Event Tap；如果仍不能稳定阻止，设置页会提示权限或降级状态。

设置页会列出检测到的 HID 与音频输入设备。若 product_id 与默认值不同，可手动选择实际的 DJI HID 设备并保存 vendor/product。

### 用 Mic Mini 中断当前流程

默认操作是：

```text
按住键盘 Ctrl
+ 按一下 DJI Mic Mini 2 按钮
= 立即中断当前听写/识别/优化/输入/等待发送流程
```

这个动作等价于 VoxForge 声铸的“中断当前流程”，不会发送回车，也不会继续等待后续识别结果。

如果 Ctrl 不顺手，可以在「设置 > DJI 触发器 > 取消修饰键」改成：

- Option
- Command
- Shift

改完后，对应操作就是“按住所选修饰键 + 按一下 DJI 按钮”。

## 中文极速本地识别

默认识别引擎是「中文极速本地」，使用 sherpa-onnx Streaming Paraformer bilingual zh-en 的 int8 模型。它会边录音边识别，HUD 显示实时预览；结束后再做后处理和粘贴。

### 安装 sherpa runtime

先安装 CMake，然后运行：

```bash
bash script/setup_sherpa_onnx.sh
```

脚本会构建 sherpa-onnx 并复制 `.dylib` 到：

```text
Vendor/SherpaRuntime
```

打包脚本会把这些动态库复制到 `.app/Contents/Frameworks`。

### 下载中文模型

方式一：在「设置 > 通用」点击「下载/重试」。

方式二：命令行续传下载：

```bash
bash script/download_paraformer_model.sh
```

模型会保存到：

```text
~/Library/Application Support/TypeMore/Models
```

说明：为保留已下载模型和历史记录，当前版本的数据目录暂沿用 `TypeMore`。分发包和界面名称已经改为 VoxForge 声铸。

如果 GitHub Release 大文件下载慢，命令行脚本支持断点续传。

## 识别引擎

可在「设置 > 通用 > 识别引擎」切换：

- 中文极速本地：默认，速度优先，适合中文和中英混说。
- WhisperKit 流式：高精度实验模式。
- WhisperKit 兼容：录音结束后整段转写，用作手动兜底。
- Apple 原生听写：预留给 macOS 26+ SpeechAnalyzer，当前未启用。

VoxForge 声铸不会在识别引擎不可用时静默切换。若 sherpa runtime 或模型缺失，会提示原因，请手动修复或切换引擎。

## 大模型优化

在「设置 > 大模型」启用。

- Base URL 默认：`https://api.openai.com/v1`
- 模型默认：`gpt-4.1-mini`
- API Key：存入系统钥匙串，不写入 `UserDefaults`
- 自定义提示词变量：`{rawTranscript}`、`{cleanedText}`、`{mode}`、`{app}`、`{style}`

处理顺序：

```text
语音识别原始文本
-> 本地口头禅/术语清理
-> 可选大模型优化
-> 粘贴到目标应用
```

如果大模型请求失败，会降级使用本地清理结果，并在 HUD 和主界面提示。

## 界面说明

- 主窗口：模式切换、最近输入、历史记录和权限提示。
- 设置窗口：通用、应用配置、大模型、DJI 触发器、隐私、关于。
- 菜单栏：常驻入口，使用卡通头像图标显示当前状态。
- HUD：位于屏幕底部 Dock 上方，使用半透明磨砂玻璃效果，不抢焦点。
- 关于页：显示版本、作者 super dan 和简短产品说明。

## 隐私与本地数据

- 默认不保存原始音频。
- 只有开启「保留录音调试文件」时才保存调试音频。
- 文本历史保存在本机，可在「设置 > 隐私」清空。
- API Key 存入系统钥匙串；旧版 `com.typemore.app` 服务下的 API Key 会在读取时迁移到 `com.voxforge.app`。
- 大模型优化只处理文本；音频不会因为 LLM 优化上传。

## 常见问题

### 快捷键没有反应

确认正在运行的是 `dist/VoxForge.app`，并检查「设置 > 通用」里的快捷键状态。如果系统设置中曾授权旧路径的 TypeMore，删除旧项后重新添加当前 `dist` 中的 VoxForge。

### 已开启辅助功能权限但无法输入

macOS 的辅助功能授权绑定 app 路径和签名。请关闭 VoxForge 声铸，在系统设置中删除旧 TypeMore/VoxForge 项，重新添加当前 `dist/VoxForge.app`，再重启应用。

### DJI 按钮仍然调高系统音量

确认「DJI 触发器」已启用，并选择了实际的 DJI HID 设备。若状态显示权限缺失，请允许输入监控/辅助功能权限。若设备被系统或其他软件占用，VoxForge 声铸会降级为 Event Tap，仍可能无法完全阻止音量变化。

### 中文被识别成英文或 “speaking in foreign language”

在「设置 > 通用 > 听写语言」选择“中文优先”，并确认识别引擎不是英文模式。

### 模型下载很慢

使用命令行下载脚本：

```bash
bash script/download_paraformer_model.sh
```

它会尽量断点续传。

## 开发命令

```bash
# 测试
swift test

# 构建并启动
./script/build_and_run.sh

# 构建并验证进程启动
./script/build_and_run.sh --verify

# 运行日志
./script/build_and_run.sh --logs

# telemetry 日志
./script/build_and_run.sh --telemetry
```

## 分发

`Packaging/notarize.sh` 会创建 `dist/VoxForge.dmg`、验证签名，并在设置 `NOTARY_PROFILE` 后提交 notarytool。

```bash
NOTARY_PROFILE=your-profile Packaging/notarize.sh
```
