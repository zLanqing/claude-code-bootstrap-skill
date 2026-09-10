---
name: claude-code-bootstrap
description: 部署或修复个人的 Claude Code 环境配置（会话恢复、开机自启、
  Auto 模式、通知提醒、应急启动脚本、progress.md 记录策略等）。当用户说"帮我部署/
  恢复我的 Claude Code 环境配置""在这台新电脑上装一下我的 Claude Code 设置"
  "我的 Claude Code 配置被改乱了，帮我修复"，或类似意图时触发。
---

当被触发时：
1. 确认当前操作系统是 Windows、终端是 PowerShell 7（pwsh），如果不是，先向用户确认
   环境是否一致，必要时调整脚本里的路径写法。
2. 依次询问用户以下机器相关信息（不要用任何旧设备的默认值去猜）：
   - PowerShell 7 的 profile 文件实际路径（可以用 `$PROFILE` 命令帮用户直接查出来，
     不用靠用户口头回忆）
   - 想要使用的默认项目目录完整路径
   - 是否需要配置开机自启（是/否）
   - 提醒方式：声音、弹窗、两者都要，还是都不要
3. 用收集到的信息运行 `scripts/apply-setup.ps1`，把对应参数传进去：
   ```powershell
   pwsh -NoProfile -File scripts/apply-setup.ps1 -ProjectFolder "<项目目录>" -ProfilePath "<profile路径>" -EnableAutoStart $true/$false -NotifyMode "sound"/"popup"/"both"/"none"
   ```
4. 脚本运行完成后，向用户复述一遍都配置了哪些内容，哪些是新增的、哪些是已存在
   跳过的、哪些是因配置变化而更新的，方便用户核对。

## 脚本行为说明

脚本是**幂等**的，支持两种场景：
- **首次部署**：检测到缺失的配置项会自动创建
- **重新运行**：检测到配置已存在但内容已变化时会自动更新（比如换了项目目录、改了通知模式）

具体行为：
| 配置项 | 首次运行 | 重新运行（内容变化） | 重新运行（内容一致） | 禁用时 |
|--------|----------|----------------------|----------------------|--------|
| claude 函数 | 写入 | 跳过（内容固定） | 跳过 | - |
| claude-new 函数 | 写入 | 跳过（内容固定） | 跳过 | - |
| emergency-start.ps1 | 创建 | 自动更新 | 跳过 | - |
| notify.ps1 | 创建 | 自动更新 | 跳过 | 删除 |
| hooks.Notification | 配置 | 自动更新 | 跳过 | 移除 |
| 桌面快捷方式 | 创建 | 自动更新 WorkingDirectory | 跳过 | - |
| 开机自启脚本 | 创建 | 自动更新 | 跳过 | 删除 |
| CLAUDE.md 策略 | 追加 | 跳过（只检查是否存在） | 跳过 | - |
