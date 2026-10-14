# SPEC.md

WinUtil 的项目契约 —— 项目是什么、如何构建、如何运行。面向任何需要理解本项目本身的人，无论是人类还是 AI。

仓库根目录的 `AGENTS.md` 会指向本文件获取这些事实，并另行说明 agent 在本仓库中工作时应如何行事。本文件不会因阅读者的不同而改变。

## 项目背景

WinUtil 是一个带 WPF 界面的 Windows PowerShell 工具。仓库以模块化源码的形式维护，但分发的产物是一个编译后的 PowerShell 脚本。

### 技术栈

- 语言：Windows PowerShell / PowerShell。
- UI：通过 `xaml/inputXML.xaml` 实现的 WPF。
- 配置：`config/` 下的 JSON 文件。
- 测试：`pester/` 下的 Pester 测试。
- 代码检查：PowerShell Script Analyzer，设置位于 `lint/PSScriptAnalyser.ps1`。
- 文档：`docs/` 下的 Astro + Starlight 站点，独立于 `Compile.ps1` 构建（有自己的 `package.json`/`node_modules`）。
- 发布产物：生成的根目录 `winutil.ps1`。

### 仓库结构

- `Compile.ps1`：生成 `winutil.ps1` 的构建脚本。
- `scripts/start.ps1`：编译后脚本开头使用的启动/引导片段。
- `scripts/main.ps1`：追加在编译后脚本末尾的主入口。
- `functions/public/`：面向 UI 的公开 PowerShell 函数。
- `functions/private/`：内部辅助 PowerShell 函数。
- `config/`：在编译时读取并嵌入到 `$sync.configs` 的 JSON 配置。
- `xaml/inputXML.xaml`：嵌入到编译后脚本中的 WPF UI 标记。
- `tools/autounattend.xml`：为 Windows ISO 工作流嵌入的无人值守安装 XML。
- `pester/`：针对配置与函数检查的 Pester 测试。
- `lint/PSScriptAnalyser.ps1`：PowerShell Script Analyzer 设置。
- `tools/title-screen/`：一个 uv 项目，用于截取 WinUtil 的 Light 与 Dark 主题，并生成标题画面合成图。
- `docs/`：Astro + Starlight 文档站点，有自己的 `package.json`，构建独立于 `Compile.ps1`。
- `winutil.ps1`：被忽略的生成产物。

## 目标

- 提供一个可从 PowerShell 启动的单脚本 Windows 工具。
- 保持开发具备足够的模块化程度，使贡献者可以分别独立地处理函数、配置、UI、文档与工具链。
- 让安装、优化项、功能、修复、更新以及 ISO 工作流都能在 WPF UI 中找到。
- 尽可能把常用列表与选项以声明式方式保存在 JSON 配置中。
- 保持可重复的编译流程，使本地构建与 GitHub Actions 构建都能从相同的输入生成可分发的脚本。

## 非目标

- `winutil.ps1` 不是手工维护的。
- 项目在运行时并非按 PowerShell 模块的形式组织。
- 在本仓库的常规发布路径中，GUI 不是一个独立打包的桌面应用程序。
- 生成的文件不应作为源码改动来评审。

## 构建模型

`Compile.ps1` 按以下顺序将仓库源文件合并为 `winutil.ps1`：

1. 读取 `scripts/start.ps1`，并将 `#{replaceme}` 替换为当前 `yy.MM.dd` 构建日期。
2. 递归追加 `functions/` 下的每个文件。
3. 将每个 `config/*.json` 文件转换为嵌入的 `$sync.configs` 对象。
4. 对 `config/applications.json` 做特殊处理，使其键在编译后的配置中带上 `WPFInstall` 前缀。
5. 将 `xaml/inputXML.xaml` 嵌入到 `$inputXML`。
6. 将 `tools/autounattend.xml` 嵌入到 `$WinUtilAutounattendXml`。
7. 追加 `scripts/main.ps1`。
8. 将结果写入根目录的 `winutil.ps1`。

由于最终脚本是拼接而成的，代码不能依赖运行时模块导入或相对于源码的点操作符加载（dot-sourcing），除非编译后的脚本同样包含所需的代码/数据。

## 运行时模型

- WinUtil 在 Windows 上的 PowerShell 中运行，并使用 WPF 作为 UI。
- 共享的可变状态存放在 `$sync` 中，包括配置、UI 元素引用、运行空间状态、选择项与进度。
- 耗时操作使用运行空间（Runspace）或现有的异步模式，以保持 UI 的响应性。
- 来自后台工作的 UI 更新会被调度回 WPF UI 线程。
- 应用、优化项、预设、DNS 提供商、导航等声明式功能保留在 `config/*.json` 中，除非确实需要代码。

## UI 与事件契约

- UI 布局位于 `xaml/inputXML.xaml`。
- 具名的 WPF 控件会被发现并存入 `$sync`。
- 按钮/动作的接线遵循命名约定：名为 `WPFThingButton` 的元素映射到名为 `Invoke-WPFThingButton` 的函数。

## 配置契约

- 配置文件必须保持为合法 JSON，并能通过 `ConvertFrom-Json` 无错解析。
- `config/dns.json` 通过 `BenchmarkEligible: true` 让未被过滤的提供商参与 Fastest 选择；缺失或为 false 的取值会使该提供商被排除在 TCP 延迟基准测试之外。
- `config/applications.json` 定义可安装的应用程序；每个条目都包含测试与 UI 代码所期望的字段，例如包管理器 ID、category、展示内容、description 和 link。
- `config/tweaks.json` 定义 Windows 优化项；注册表与服务类更改在适用时会包含原始值或原始状态，以便撤销工作流能够还原用户系统。
- 预设与导航文件引用合法的配置键。重命名某个配置键时，需要同时更新所有预设、UI 引用、文档与代码路径。

## 安全要求

- 注册表、服务、包管理器、Windows Update、AppX 卸载与 ISO 操作都会影响宿主系统，被视为高风险操作。
- 在结构支持的情况下，优化项更改会包含撤销元数据，从而保持更改可逆。
- ISO 工作流绝不修改用户的原始 ISO 文件；它们只作用于复制/挂载后的内容。

## 文档站（Astro）

- `docs/` 是一个 Astro + Starlight 站点，独立于 `Compile.ps1` 的构建（有自己的 `package.json`/`node_modules`，通过 `docs.yaml` GitHub Actions 工作流部署到 GitHub Pages）。
- 页面位于 `docs/src/content/docs/`（`.mdx`），分为 `guides/`、`code-reference/`，以及 `faq.mdx`、`knownissues.mdx`、`contributing.mdx`、`index.mdx` 等顶层页面。
- `docs/src/content/docs/code-reference/tweaks/` 与 `.../features/` 由 `tools/devdocs-generator.ps1` 从 `config/tweaks.json`/`config/feature.json` 以及相关的 PowerShell 函数文件自动生成。`code-reference/` 下的其他页面（例如 `architecture.mdx`）是手写的，生成器不会改动它们。
- `docs/astro.config.mjs` 中的侧边栏条目必须与 `docs/src/content/docs/` 下实际的页面 slug 一致。
- `docs/public/` 是静态资源（favicon 等）的受跟踪源码，而非生成产物。被生成/忽略的路径列在 `docs/.gitignore` 中（`dist/`、`.astro/`、`node_modules/`、本地 env 文件）。
- `docs/src/assets/branding/title-screen.png` 是一张受跟踪的生成图片，供仓库 README 与文档首页使用。其原始的 Light 与 Dark 截图是临时文件。
- `docs/Dockerfile` 与 `docs/docker-compose.yml`（服务 `winutil-astro`）将该站点的 npm 工具链容器化；关于为何以及如何使用它们、而不是在宿主机上直接运行 npm，请参阅 AGENTS.md 的 Dependency Installs, Builds, And Dev Servers 一节。

## 测试与 CI

- `.\Compile.ps1` 用于验证编译器能够生成 `winutil.ps1`。
- `.\Compile.ps1 -Run` 会编译并启动生成的工具，以便人工验证 GUI。
- Pester 5.8.0 运行 `pester/*.Tests.ps1` 下的测试套件。GitHub Actions（`unittests.yaml`）会全新安装 Pester 5.8.0 并以 `-CI` 运行，产出 `testResults.xml`，失败时以非零码退出。
- GitHub Actions 还会在每次 push 时使用 `lint/PSScriptAnalyser.ps1` 运行 PowerShell Script Analyzer。
- 生成的 `winutil.ps1` 可能在编译后出现在本地。它仍然是被忽略的构建产物（见根目录 `.gitignore`），不得提交。
- 手动触发的标题画面工作流会从 `main` 编译 WinUtil，并在生成的合成图发生变化时开启一个仅含图片的 pull request。这些 pull request 需要人工评审。失败的运行会保留诊断信息 14 天。

## 发布产物

GitHub Actions 负责从仓库源码生成发布的 `winutil.ps1`。只有当生成的脚本来自编译流程、而非对 `winutil.ps1` 的直接手工编辑时，该发布才被视为有效。
