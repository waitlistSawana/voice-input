# VoiceInput

[English](./README.md) | 中文

一个实验性的 macOS 菜单栏语音输入应用，面向快速的按住说话式听写。

`VoiceInput` 支持按住 `Fn` 录音、松开后将文本注入当前聚焦的输入框，并且可以在粘贴前选择性地执行一次非常保守的 LLM refine。它面向 macOS 14+，默认语言为简体中文，并采用轻量的菜单栏工作流，而不是传统的 Dock 应用形态。

> 当前状态：这是一个实验项目，但仓库结构已经按可交付形态整理。核心链路已经实现，可构建打包，当前存在的粗糙点也在下文明确列出。

## 亮点

- 基于全局按键监听的 `Fn` 按住说话交互
- 使用 Apple Speech Recognition 的流式转录
- 默认语言为 `zh-CN`，菜单栏可切换英语、简体中文、繁体中文、日语、韩语
- 基于 `NSPanel` 和 `NSVisualEffectView` 的底部 HUD
- 实时音频电平驱动的波形反馈链路
- 面向 CJK 输入法的文本注入方案，注入前可临时切换到 ASCII 输入源
- 可选的 OpenAI 兼容 LLM refine，用于非常保守的识别纠错
- 基于 Swift Package Manager 与 `Makefile` 的 `LSUIElement` 应用打包流程

## 为什么会有这个项目

这个仓库最初是受到 [yetone/voice-input-src](https://github.com/yetone/voice-input-src) 的启发。那个仓库本质上更像是“把 prompt 开源出来”。我以这个思路为起点，再把 prompt 交给集成了 [obra/superpowers](https://github.com/obra/superpowers) 工作流的 Codex，继续迭代成一个真正的 Swift 工程，补上测试、打包和文档。

所以这个仓库不只是 prompt 存档。它是这次实验真正产出的实现代码，并且被保留在一个可以构建、检查、测试和继续往前 ship 的状态。

## 它做了什么

当你按住 `Fn` 时，`VoiceInput` 会通过 `AVAudioEngine` 开始录音，并把音频流送入 Apple 语音识别。说话过程中，底部 HUD 会显示实时转录文本和波形反馈。松开 `Fn` 后，会话会收尾 transcript，可选地发给一个非常保守的 LLM refine，再把最终文本通过剪贴板粘贴注入到当前聚焦的输入框。

为了避免 CJK 输入法吞掉 `Cmd+V`，应用在注入前可以临时切换到 ASCII 输入源，并在注入后恢复原始输入法。

## 快速开始

环境要求：

- macOS 14+
- Xcode Command Line Tools
- `Accessibility` 权限
- `Microphone` 权限
- `Speech Recognition` 权限

构建 `.app`：

```bash
make build
```

本地运行：

```bash
make run
```

安装到 `/Applications`：

```bash
make install
```

清理本地构建产物：

```bash
make clean
```

生成的应用包位置：

```text
dist/VoiceInput.app
```

## 权限

`VoiceInput` 正常工作需要 3 项 macOS 权限：

- `Accessibility`：用于全局监听 `Fn`、模拟粘贴和输入源切换
- `Microphone`：用于音频采集
- `Speech Recognition`：用于 Apple 语音转录

当前实现假设用户会在系统弹窗或系统设置中手动授予这些权限。

## LLM Refine

LLM refine 是可选功能；只有在配置完成后才能启用。

菜单栏里提供了 `LLM Refinement` 子菜单，包含：

- 启用或禁用开关
- `Settings...` 设置窗口
- `API Base URL`、`API Key`、`Model` 三个字段
- 连通性测试动作

refine prompt 被故意设计得非常保守。模型只应修复明显的识别错误，尤其是中英混杂时的技术术语误识别，例如把 `配森` 修正为 `Python`、把 `杰森` 修正为 `JSON`，而不是润色或改写本来已经正确的文本。

## 项目结构

```text
Sources/AppMain   应用入口与生命周期编排
Sources/Core      语音、热键、注入、设置、权限、LLM 逻辑
Sources/UI        菜单栏 UI、悬浮 HUD、设置窗口
Resources         Info.plist、entitlements、图标资源
Tests             Core、UI 与 smoke tests
docs              规格、计划与手工验证记录
```

## 当前缺口

这个仓库已经可用，但并不假装自己已经打磨完成。根据当前手工验证结果：

- HUD 波形在真实使用中的视觉表现仍有问题，需要配合录屏做一次认真验证
- 从菜单栏退出后，系统 `Fn` 长按原生行为的恢复可能不够干净
- 轻声输入当前不如正常音量稳定
- 目前只有本地 `make` 打包流程，还没有更完整的 release pipeline

这些都是当前真实存在的产品质量缺口，不是藏在角落里的备注。

## 验证

仓库里包含核心状态机与打包流程的自动化测试，也包含手工验证清单：

- [英文手工清单](./docs/manual-test-checklist.md)
- [中文手工清单](./docs/manual-test-checklist.zh-CN.md)

常用验证命令：

```bash
swift test
make build
```

## 灵感来源

- [yetone/voice-input-src](https://github.com/yetone/voice-input-src)
- [obra/superpowers](https://github.com/obra/superpowers)

## License

仓库目前还没有加入 license 文件。
