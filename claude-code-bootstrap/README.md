# Claude Code Bootstrap

---

一个 Claude Code Skill，用于在新电脑或配置被改乱的电脑上，一键恢复个人的 Claude Code 使用环境：会话恢复、应急启动、自动归档、进度记录、通知提醒、开机自启。全部通过交互式问答收集机器相关信息后自动完成，不写死任何个人路径。

![Platform](https://img.shields.io/badge/Platform-Windows-orange) ![Shell](https://img.shields.io/badge/Shell-PowerShell%207-2E8B57) ![Language](https://img.shields.io/badge/Language-Chinese--first-red) ![License](https://img.shields.io/badge/License-MIT-blue) ![Skills](https://img.shields.io/badge/Skills-1-8A2BE2)

## 这个 Skill 解决什么问题

Claude Code 本身不会记住"我习惯怎么用它"：换一台电脑、重装系统，或者不小心把 `settings.json` / PowerShell profile 改乱之后，之前攒的这套顺手的工作流（session resume、双重通知、任务文件夹管理……）都要手动重搭一遍。这个 Skill 把整套个人配置沉淀成脚本 + 说明，触发一次对话就能在新环境里原样复原。

## 对新手也很友好

如果你刚开始用 Claude Code，还没时间摸索"怎么配置才顺手"，这个 Skill 同样适合你——不需要你先懂 PowerShell、懂 `settings.json` 的结构、懂 hooks 是什么，全程只需要回答几个简单问题（项目目录放哪、要不要开机自启、想要哪种提醒方式），剩下的都交给 Claude Code 自动完成。

对新手来说，它实际解决的是几个很容易被忽略、但用久了才会意识到很烦人的问题：

- **不会写会话恢复脚本？** 装好之后 `claude` 命令自动帮你接着上次的对话，不用每次都翻聊天记录找上下文
- **不知道怎么组织任务文件夹？** 提供现成的"应急启动"入口：弹窗选文件夹、列出最近任务、自动归档旧任务，不用自己想命名规则和整理方式
- **Claude Code 中途"失忆"？** 内置 `progress.md` 记录策略，重新打开老任务时自动先读进度，不用重复解释背景
- **等 Claude Code 处理完却没注意到？** 一次性配好声音/弹窗提醒，不用一直盯着终端
- **每次开机都要手动敲命令启动？** 可选开机自启，登录即可用

也就是说，这个 Skill 本质上是把"一个用了很久 Claude Code 的人总结出来的最佳实践"打包成了一次性可复用的配置，新手不用自己踩一遍坑、也不用理解背后每个配置项的作用，就能直接获得一套顺手的工作流，从第一天起就更高效地使用 Claude Code。

## 功能总览

| 功能 | 说明 |
| --- | --- |
| 会话恢复（`claude` 函数） | 覆盖默认 `claude` 命令，自动 `--resume`，找不到历史记录时自动降级为全新会话 |
| 应急启动（`claude-new` 函数 + 桌面快捷方式） | 弹出原生文件夹选择框 → 继续已有任务 / 新建任务 → 自动定位并启动 Claude Code |
| 自动归档 | 每次运行应急启动脚本时，自动把 30 天内无文件变动的任务文件夹移入 `_archive` |
| 任务列表 | 默认只显示最近 9 个活跃任务，超出部分可输入 `all` 展开，也支持关键词搜索（含已归档任务） |
| progress.md 记录策略 | 写入 `~/.claude/CLAUDE.md`，让 Claude Code 在关键节点自动读写任务进度，避免重新打开老任务文件夹时"失忆" |
| 通知提醒 | 声音 / 弹窗 / 两者都要 / 都不要，四选一，写入 `hooks.Notification` |
| 开机自启 | 可选，登录后自动在默认项目目录 `--resume` 启动 Claude Code |
| Auto 权限模式 | 写入 `permissions.defaultMode: auto`，减少每步确认，仍会在敏感操作时询问 |

## 技能触发方式

对 Claude Code 说以下任意一句均可触发：

> "帮我部署我的 Claude Code 环境配置"
> "在这台新电脑上装一下我的 Claude Code 设置"
> "我的 Claude Code 配置被改乱了，帮我修复"

## 安装

### 方式一：直接克隆

```bash
git clone <your-repo-url> ~/.claude/skills/claude-code-bootstrap
```

### 方式二：通过插件市场（如果已配置）

```bash
/plugin install claude-code-bootstrap
```

> Windows 用户注意：`~/.claude/skills/` 对应 `%USERPROFILE%\.claude\skills\`。

## 使用

安装完成后，按上文"触发方式"说一句即可。Claude Code 会依次询问：

1. 确认当前系统是 Windows + PowerShell 7（pwsh），不是的话先确认环境差异
2. PowerShell 7 的 profile 文件实际路径（会用 `$PROFILE` 帮你直接查，不用凭记忆）
3. 默认项目目录完整路径
4. 是否需要开机自启（是 / 否）
5. 通知方式（声音 / 弹窗 / 两者都要 / 都不要）

收集完成后，Skill 会调用 `scripts/apply-setup.ps1` 并传入以上参数，运行结束后向你复述一遍：哪些是新增的、哪些是已存在跳过的、哪些是因配置变化而更新的，方便核对。

## 部署内容详解

脚本是**幂等**的，支持两种场景：
- **首次部署**：检测到缺失的配置项会自动创建
- **重新运行**：检测到配置已存在但内容已变化时会自动更新（比如换了项目目录、改了通知模式）

| 目标文件 | 首次运行 | 重新运行（内容变化） | 禁用时 |
| --- | --- | --- | --- |
| PowerShell Profile | 新增 `claude` 和 `claude-new` 函数 | 跳过（内容固定） | - |
| `<项目目录>/_scripts/emergency-start.ps1` | 创建 | 自动更新 | - |
| `~/.claude/settings.json` | 合并写入配置 | 合并写入配置 | - |
| `~/.claude/hooks/notify.ps1` | 创建 | 自动更新 | 删除 |
| `hooks.Notification` | 配置 | 自动更新 | 移除 |
| `~/.claude/CLAUDE.md` | 追加策略章节 | 跳过（只检查是否存在） | - |
| 桌面快捷方式 | 创建 | 自动更新 WorkingDirectory | - |
| 开机启动项 | 创建 | 自动更新 | 删除 |

### 脚本参数（`apply-setup.ps1`）

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `-ProjectFolder` | 是 | 默认项目目录完整路径 |
| `-ProfilePath` | 是 | PowerShell 7 profile 文件路径 |
| `-EnableAutoStart` | 否（默认 `$true`） | 是否配置开机自启 |
| `-NotifyMode` | 否（默认 `both`） | `sound` / `popup` / `both` / `none` |

## 适用场景

- 🖥️ 换新电脑时一键部署
- 🔧 当前电脑配置被改乱时修复（脚本会跳过已存在的部分，不会重复写入或破坏）
- 🔄 重装系统后快速恢复
- 🧭 给同一台电脑上的新用户账号复制一份同样的工作流
- 🆕 刚接触 Claude Code、还不熟悉如何配置的新手，想直接获得一套顺手的默认工作流
- 🔄 想修改配置时（换了项目目录、改了通知模式），重新运行即可自动更新

## 注意事项

- 本 Skill 不包含任何账号密码、密钥等敏感信息
- 所有路径通过交互式询问获取，不写死个人路径；不会用旧设备的默认值去猜新设备
- 目前仅针对 Windows + PowerShell 7（pwsh）环境；其他终端/系统需要先跟 Claude 确认环境差异，必要时调整脚本里的路径写法
- 建议将 GitHub 仓库设为 private（虽然脚本本身不含敏感信息，但里面体现了你的个人使用习惯）
- 脚本支持幂等运行，可以重复执行不会产生重复配置

## 目录结构

```
claude-code-bootstrap/
├── SKILL.md                  # 触发条件与执行步骤定义
├── README.md                 # 本文档
└── scripts/
    └── apply-setup.ps1       # 实际执行部署的 PowerShell 脚本
```
