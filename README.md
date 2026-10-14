# Chris Titus Tech 的 Windows 实用工具

[![Version](https://img.shields.io/github/v/release/ChrisTitusTech/winutil?color=%230567ff&label=Latest%20Release&style=for-the-badge)](https://github.com/ChrisTitusTech/winutil/releases/latest)
![Downloads](https://img.shields.io/github/downloads/ChrisTitusTech/winutil/winutil.ps1?label=Total%20Downloads&style=for-the-badge)
[![Discord](https://dcbadge.limes.pink/api/server/https://discord.gg/RUbZUZyByQ?theme=default-inverted&style=for-the-badge)](https://discord.gg/RUbZUZyByQ)

一套精心整理的 Windows 系统任务合集：用**安装**功能简化软件部署、用**优化项**清理预装冗余软件、用**配置**排查故障，并管理 **Windows 更新**。建议每次全新安装 Windows 后都运行一遍。

![Title Screen](docs/src/assets/branding/title-screen.png)


---

## 快速开始

> **WinUtil 必须以管理员身份运行**，因为它会执行系统范围的更改。

以管理员身份打开 PowerShell 或终端，然后运行：

**稳定分支（推荐）**
```ps1
irm https://christitus.com/win | iex
```

**开发分支**
```ps1
irm https://christitus.com/windev | iex
```

### 如何打开管理员终端

- **开始菜单：** 右键点击「开始」→ *Windows PowerShell（管理员）* 或 *终端（管理员）*
- **搜索：** 按下 `Windows key`，输入 `PowerShell` 或 `Terminal`，然后按 `Ctrl + Shift + Enter`

---

## 自动化 / 预设

无需手动勾选，直接应用一套预先定义好的配置：

```powershell
& ([ScriptBlock]::Create((irm https://christitus.com/win))) -Preset Standard
```

| 预设 | 说明 |
|--------|-------------|
| `Standard` | 适合大多数用户的均衡默认配置 |
| `Minimal` | 改动最小，适合所有用户 |
| `Advanced` | 面向高级用户的深度优化项 |

想了解每个预设具体做了什么，请查看：
https://github.com/ChrisTitusTech/winutil/blob/main/config/preset.json

---

## 构建与开发

参见 https://github.com/ChrisTitusTech/winutil/blob/main/.github/CONTRIBUTING.md

---

## 资源

- [官方文档](https://winutil.christitus.com/)
- [YouTube 教程](https://www.youtube.com/watch?v=6UQZ5oQg8XA)
- [ChrisTitus.com 文章](https://christitus.com/windows-tool/)
- [已知问题](https://winutil.christitus.com/knownissues/)
- [提交问题反馈](https://github.com/ChrisTitusTech/winutil/issues)

---

## 支持

- 点个 ⭐ 表示支持吧！
- 更快的 Dotnet 实现版本在此购买：https://www.cttstore.com/windows-toolbox

## 赞助者

以下是通过每月捐助支持本项目持续运转的赞助者。

<!-- sponsors --><a href="https://github.com/dwelfusius"><img src="https:&#x2F;&#x2F;github.com&#x2F;dwelfusius.png" width="60px" alt="User avatar: " /></a><a href="https://github.com/mews-se"><img src="https:&#x2F;&#x2F;github.com&#x2F;mews-se.png" width="60px" alt="User avatar: Martin" /></a><a href="https://github.com/jdiegmueller"><img src="https:&#x2F;&#x2F;github.com&#x2F;jdiegmueller.png" width="60px" alt="User avatar: Jason A. Diegmueller" /></a><a href="https://github.com/robertsandrock"><img src="https:&#x2F;&#x2F;github.com&#x2F;robertsandrock.png" width="60px" alt="User avatar: RMS" /></a><a href="https://github.com/paulsheets"><img src="https:&#x2F;&#x2F;github.com&#x2F;paulsheets.png" width="60px" alt="User avatar: Paul" /></a><a href="https://github.com/djones369"><img src="https:&#x2F;&#x2F;github.com&#x2F;djones369.png" width="60px" alt="User avatar: Dave J  (WhamGeek)" /></a><a href="https://github.com/anthonymendez"><img src="https:&#x2F;&#x2F;github.com&#x2F;anthonymendez.png" width="60px" alt="User avatar: Anthony Mendez" /></a><a href="https://github.com/FatBastard0"><img src="https:&#x2F;&#x2F;github.com&#x2F;FatBastard0.png" width="60px" alt="User avatar: " /></a><a href="https://github.com/DursleyGuy"><img src="https:&#x2F;&#x2F;github.com&#x2F;DursleyGuy.png" width="60px" alt="User avatar: DursleyGuy" /></a><a href="https://github.com/DwayneTheRockLobster1"><img src="https:&#x2F;&#x2F;github.com&#x2F;DwayneTheRockLobster1.png" width="60px" alt="User avatar: " /></a><a href="https://github.com/KieraKujisawa"><img src="https:&#x2F;&#x2F;github.com&#x2F;KieraKujisawa.png" width="60px" alt="User avatar: Kiera Meredith" /></a><a href="https://github.com/seanh1995"><img src="https:&#x2F;&#x2F;github.com&#x2F;seanh1995.png" width="60px" alt="User avatar: Sean (ANGRYxScotsman)" /></a><a href="https://github.com/josencarnacao"><img src="https:&#x2F;&#x2F;github.com&#x2F;josencarnacao.png" width="60px" alt="User avatar: José Encarnação" /></a><!-- sponsors -->

*<sub>拥有周期性订阅的赞助者还可获得 .NET 版本的使用权限。</sub>

---

## 贡献者

[![Contributors](https://contrib.rocks/image?repo=ChrisTitusTech/winutil)](https://github.com/ChrisTitusTech/winutil/graphs/contributors)

感谢所有为本项目投入时间与精力的朋友。继续加油 🍻
