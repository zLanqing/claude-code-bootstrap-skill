param(
    [Parameter(Mandatory=$true)][string]$ProjectFolder,
    [Parameter(Mandatory=$true)][string]$ProfilePath,
    [bool]$EnableAutoStart = $true,
    [ValidateSet("sound","popup","both","none")][string]$NotifyMode = "both"
)

Write-Host "开始部署 Claude Code 个人环境配置..." -ForegroundColor Cyan

# --- 1. claude / claude-new 函数写入 profile ---
$profileContent = if (Test-Path $ProfilePath) { Get-Content $ProfilePath -Raw } else { "" }

if ($profileContent -notmatch "function claude\s*\{") {
    Add-Content -Path $ProfilePath -Value @'
function claude {
    $claudeReal = Get-Command claude -All -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -ne "Function" } |
        Select-Object -First 1 -ExpandProperty Source
    if (-not $claudeReal) {
        Write-Host "找不到 claude 可执行文件，请检查安装或 PATH 配置" -ForegroundColor Red
        return
    }
    $result = & $claudeReal --resume @args 2>&1
    if ($LASTEXITCODE -ne 0) { & $claudeReal @args } else { $result }
}
'@
    Write-Host "已写入 claude 函数" -ForegroundColor Green
} else {
    Write-Host "claude 函数已存在，跳过" -ForegroundColor DarkGray
}

$scriptsDir = Join-Path $ProjectFolder "_scripts"
New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null

if ($profileContent -notmatch "function claude-new\s*\{") {
    Add-Content -Path $ProfilePath -Value @"
function claude-new {
    & "$scriptsDir\emergency-start.ps1"
}
"@
    Write-Host "已写入 claude-new 函数" -ForegroundColor Green
} else {
    Write-Host "claude-new 函数已存在，跳过" -ForegroundColor DarkGray
}

# --- 2. 生成 emergency-start.ps1 ---
$emergencyScriptPath = Join-Path $scriptsDir "emergency-start.ps1"
$emergencyScriptContent = @'
Add-Type -AssemblyName System.Windows.Forms

# 第一步：弹出原生选文件夹窗口
$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = "选择项目文件夹"
$dialog.ShowNewFolderButton = $true

if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "未选择文件夹，已取消启动。" -ForegroundColor Yellow
    return
}
$projectFolder = $dialog.SelectedPath

$archiveFolder = Join-Path $projectFolder "_archive"
if (-not (Test-Path $archiveFolder)) {
    New-Item -ItemType Directory -Path $archiveFolder -Force | Out-Null
}

# 第二步：自动归档——超过 30 天没有文件变动的任务文件夹，移入 _archive
$archiveThresholdDays = 30
$cutoffDate = (Get-Date).AddDays(-$archiveThresholdDays)

$candidateFolders = Get-ChildItem -Path $projectFolder -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne "_archive" -and $_.Name -ne "_scripts" }

foreach ($folder in $candidateFolders) {
    $lastActivity = Get-ChildItem -Path $folder.FullName -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty LastWriteTime

    if (-not $lastActivity) {
        $lastActivity = $folder.LastWriteTime
    }

    if ($lastActivity -lt $cutoffDate) {
        $destination = Join-Path $archiveFolder $folder.Name
        if (-not (Test-Path $destination)) {
            Move-Item -Path $folder.FullName -Destination $destination
            Write-Host "已自动归档超过 $archiveThresholdDays 天未使用的任务：$($folder.Name)" -ForegroundColor DarkGray
        }
    }
}

# 第三步：列出活跃任务文件夹，默认只显示最近 9 个，支持 all / 关键词搜索
$activeTasks = Get-ChildItem -Path $projectFolder -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne "_archive" -and $_.Name -ne "_scripts" } |
    Sort-Object LastWriteTime -Descending

$displayList = $activeTasks | Select-Object -First 9
$targetFolderPath = $null

while (-not $targetFolderPath) {
    if ($displayList.Count -gt 0) {
        Write-Host ""
        Write-Host "最近的任务文件夹：" -ForegroundColor Cyan
        for ($i = 0; $i -lt $displayList.Count; $i++) {
            Write-Host "  [$($i + 1)] $($displayList[$i].Name)"
        }
        Write-Host "  [0] 新建一个任务文件夹"
        if ($activeTasks.Count -gt $displayList.Count) {
            Write-Host "  输入 all 查看全部活跃任务（共 $($activeTasks.Count) 个）"
        }
        Write-Host "  也可以直接输入关键词搜索（含已归档的任务）"
        Write-Host ""
        $choice = Read-Host "请输入编号 / 0 新建 / all / 关键词"
    } else {
        Write-Host "该项目下暂无任务文件夹，直接新建。" -ForegroundColor Yellow
        $choice = "0"
    }

    if ($choice -match '^\d+$') {
        $num = [int]$choice
        if ($num -eq 0) {
            break
        } elseif ($num -ge 1 -and $num -le $displayList.Count) {
            $targetFolderPath = $displayList[$num - 1].FullName
        } else {
            Write-Host "编号超出范围，请重新输入。" -ForegroundColor Red
        }
    }
    elseif ($choice -ieq "all") {
        $displayList = $activeTasks
    }
    else {
        # 关键词搜索：活跃 + 已归档 一起搜
        $searchPool = @()
        $searchPool += $activeTasks
        $searchPool += (Get-ChildItem -Path $archiveFolder -Directory -ErrorAction SilentlyContinue)
        $searchResults = $searchPool | Where-Object { $_.Name -like "*$choice*" }

        if ($searchResults.Count -eq 0) {
            Write-Host "没找到匹配 '$choice' 的任务文件夹，请重新输入。" -ForegroundColor Red
        } else {
            Write-Host ""
            Write-Host "搜索结果：" -ForegroundColor Cyan
            for ($i = 0; $i -lt $searchResults.Count; $i++) {
                Write-Host "  [$($i + 1)] $($searchResults[$i].Name)"
            }
            $subChoice = Read-Host "请输入编号选择，或直接回车重新搜索"
            if ($subChoice -match '^\d+$') {
                $subNum = [int]$subChoice
                if ($subNum -ge 1 -and $subNum -le $searchResults.Count) {
                    $targetFolderPath = $searchResults[$subNum - 1].FullName
                }
            }
        }
    }
}

# 第四步：没选中已有任务（走了 0 或新建流程）
if (-not $targetFolderPath) {
    $taskName = Read-Host "请输入本次任务名称"
    if ([string]::IsNullOrWhiteSpace($taskName)) {
        $taskName = "未命名任务"
    }
    $safeTaskName = $taskName -replace '[\\/:*?"<>|]', '_'
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $taskFolderName = "${timestamp}_${safeTaskName}"
    $targetFolderPath = Join-Path $projectFolder $taskFolderName
    New-Item -ItemType Directory -Path $targetFolderPath -Force | Out-Null
    Write-Host "已创建任务文件夹：$targetFolderPath" -ForegroundColor Cyan
}

# 第五步：进入目标文件夹并启动 Claude Code
Set-Location $targetFolderPath

# 如果存在 progress.md，显示摘要
$progressFile = Join-Path $targetFolderPath "progress.md"
if (Test-Path $progressFile) {
    Write-Host ""
    Write-Host "===== progress.md 摘要 =====" -ForegroundColor Magenta
    Get-Content $progressFile | Select-Object -First 20
    Write-Host "============================" -ForegroundColor Magenta
    Write-Host ""
}

$claudeReal = Get-Command claude -All -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandType -ne 'Function' } |
    Select-Object -First 1 -ExpandProperty Source

if (-not $claudeReal) {
    Write-Host "找不到 claude 可执行文件，请检查安装或 PATH 配置" -ForegroundColor Red
    return
}

$result = & $claudeReal --resume 2>&1
if ($LASTEXITCODE -ne 0) {
    & $claudeReal
} else {
    $result
}
'@

if (Test-Path $emergencyScriptPath) {
    $existingContent = Get-Content $emergencyScriptPath -Raw
    if ($existingContent -ne $emergencyScriptContent) {
        Write-Host "emergency-start.ps1 内容已更新" -ForegroundColor Yellow
        Set-Content -Path $emergencyScriptPath -Value $emergencyScriptContent
    } else {
        Write-Host "emergency-start.ps1 已是最新，跳过" -ForegroundColor DarkGray
    }
} else {
    Set-Content -Path $emergencyScriptPath -Value $emergencyScriptContent
    Write-Host "已创建 emergency-start.ps1" -ForegroundColor Green
}

# --- 3. 合并 ~/.claude/settings.json ---
$settingsPath = "$env:USERPROFILE\.claude\settings.json"
$settings = if (Test-Path $settingsPath) {
    Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    [PSCustomObject]@{}
}

# cleanupPeriodDays
if (-not $settings.cleanupPeriodDays) {
    $settings | Add-Member -NotePropertyName "cleanupPeriodDays" -NotePropertyValue 90 -Force
    Write-Host "已添加 cleanupPeriodDays: 90" -ForegroundColor Green
} else {
    Write-Host "cleanupPeriodDays 已存在: $($settings.cleanupPeriodDays)，跳过" -ForegroundColor DarkGray
}

# permissions.defaultMode
if (-not $settings.permissions) {
    $settings | Add-Member -NotePropertyName "permissions" -NotePropertyValue ([PSCustomObject]@{ defaultMode = "auto" }) -Force
    Write-Host "已添加 permissions.defaultMode: auto" -ForegroundColor Green
} elseif (-not $settings.permissions.defaultMode) {
    $settings.permissions | Add-Member -NotePropertyName "defaultMode" -NotePropertyValue "auto" -Force
    Write-Host "已添加 permissions.defaultMode: auto" -ForegroundColor Green
} else {
    Write-Host "permissions.defaultMode 已存在: $($settings.permissions.defaultMode)，跳过" -ForegroundColor DarkGray
}

# hooks.Notification
$notifyScriptPath = "$env:USERPROFILE\.claude\hooks\notify.ps1"
$notifyDir = Split-Path $notifyScriptPath
if (-not (Test-Path $notifyDir)) {
    New-Item -ItemType Directory -Path $notifyDir -Force | Out-Null
}

if ($NotifyMode -ne "none") {
    $notifyScriptContent = @"
param(
    [string]`$Message = "Claude Code 需要你的 attention"
)

Add-Type -AssemblyName System.Windows.Forms

if ("$NotifyMode" -eq "sound" -or "$NotifyMode" -eq "both") {
    [System.Media.SystemSounds]::Hand.Play()
}

if ("$NotifyMode" -eq "popup" -or "$NotifyMode" -eq "both") {
    `$balloon = New-Object System.Windows.Forms.NotifyIcon
    `$balloon.Icon = [System.Drawing.SystemIcons]::Information
    `$balloon.BalloonTipTitle = "Claude Code"
    `$balloon.BalloonTipText = `$Message
    `$balloon.Visible = `$true
    `$balloon.ShowBalloonTip(5000)
    Start-Sleep -Seconds 6
    `$balloon.Dispose()
}
"@

    if (Test-Path $notifyScriptPath) {
        $existingContent = Get-Content $notifyScriptPath -Raw
        if ($existingContent -ne $notifyScriptContent) {
            Write-Host "notify.ps1 内容已更新 (模式: $NotifyMode)" -ForegroundColor Yellow
            Set-Content -Path $notifyScriptPath -Value $notifyScriptContent
        } else {
            Write-Host "notify.ps1 已是最新 (模式: $NotifyMode)，跳过" -ForegroundColor DarkGray
        }
    } else {
        Set-Content -Path $notifyScriptPath -Value $notifyScriptContent
        Write-Host "已创建 notify.ps1 (模式: $NotifyMode)" -ForegroundColor Green
    }

    # 配置hooks
    if (-not $settings.hooks) {
        $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $hooksNotification = @(
        @{
            matcher = "permission_prompt"
            hooks = @(@{ type = "command"; command = "pwsh -NoProfile -File `"$notifyScriptPath`"" })
        },
        @{
            matcher = "idle_prompt"
            hooks = @(@{ type = "command"; command = "pwsh -NoProfile -File `"$notifyScriptPath`"" })
        },
        @{
            matcher = "elicitation_dialog"
            hooks = @(@{ type = "command"; command = "pwsh -NoProfile -File `"$notifyScriptPath`"" })
        }
    )
    if ($settings.hooks.Notification) {
        $existingJson = $settings.hooks.Notification | ConvertTo-Json -Depth 10
        $newJson = $hooksNotification | ConvertTo-Json -Depth 10
        if ($existingJson -ne $newJson) {
            Write-Host "hooks.Notification 配置已更新" -ForegroundColor Yellow
            $settings.hooks.Notification = $hooksNotification
        } else {
            Write-Host "hooks.Notification 已是最新，跳过" -ForegroundColor DarkGray
        }
    } else {
        $settings.hooks | Add-Member -NotePropertyName "Notification" -NotePropertyValue $hooksNotification -Force
        Write-Host "已配置 hooks.Notification" -ForegroundColor Green
    }
} else {
    # NotifyMode 为 "none"，清理已有的通知配置
    if ($settings.hooks -and $settings.hooks.Notification) {
        $settings.hooks.PSObject.Properties.Remove('Notification')
        Write-Host "已移除 hooks.Notification (模式: none)" -ForegroundColor Yellow
    }
    if (Test-Path $notifyScriptPath) {
        Remove-Item -Path $notifyScriptPath -Force
        Write-Host "已删除 notify.ps1 (模式: none)" -ForegroundColor Yellow
    }
}

# 写回settings.json
$settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath
Write-Host "已更新 settings.json" -ForegroundColor Green

# --- 4. 合并 ~/.claude/CLAUDE.md ---
$claudeMdPath = "$env:USERPROFILE\.claude\CLAUDE.md"
$claudeMdContent = if (Test-Path $claudeMdPath) { Get-Content $claudeMdPath -Raw } else { "" }

# 检查并追加任务进度记录策略
if ($claudeMdContent -notmatch "## 任务进度记录策略") {
    $progressStrategy = @"

---

## 任务进度记录策略（progress.md）

### 开始任务时
每次在一个新的工作目录里开始任务前，先检查当前目录下是否存在
`progress.md`：
- 如果存在，先完整读取它，了解这个任务之前的背景、已完成的步骤、
  遇到过的问题和解决办法、当前进展，再基于这些信息继续工作，
  不要当作全新任务从头开始猜。
- 如果不存在，且这个任务看起来不是一次性的简单问答（比如涉及多个
  步骤、需要跨会话持续推进、明显会产生值得记录的过程），在完成第
  一个关键节点时创建这个文件。

### 什么时候更新
只在关键节点更新，不要每完成一个小步骤就写一次，保持文档精练：
- 解决了一个问题（尤其是排查过程比较曲折的）
- 完成了一个阶段性目标/里程碑
- 做出了一个会影响后续方向的重要决定
- 遇到一个尚未解决、需要下次接着处理的阻塞点

### 内容结构
`progress.md` 建议保持类似这样的结构（可以按实际任务调整）：

```markdown
# 任务：<任务名称/简述>

## 背景与目标
<这个任务大概是要做什么>

## 关键进展
- <日期/节点> <做了什么、解决了什么>
- <日期/节点> <做了什么、解决了什么>

## 遇到的问题与解决办法
- 问题：<问题描述>
  解决：<怎么解决的，或者"尚未解决，下一步打算怎么办">

## 当前状态 / 下一步
<现在进行到哪一步，接下来打算做什么>
```

### 更新方式
每次更新用追加或改写"当前状态/下一步"部分为主，不要整篇重写导致
早期记录丢失；同一个问题只保留一份最新的解决过程，不用把中间反复
尝试失败的细节都堆进去，保留结论和关键教训即可。

### 已有历史但缺失 progress.md 的老任务文件夹 —— 一次性补录
如果进入一个工作目录后，发现该目录下没有 `progress.md`，但本地存在
这个目录对应的历史会话记录（`~/.claude/projects/` 下能找到匹配的
会话文件），说明这是一个"已经做过一段时间、但还没启用新记录策略"
的老任务，此时：
1. 主动翻阅该目录下所有可用的历史会话记录，梳理出：这个任务大概
   是要做什么、已经完成了哪些关键步骤、遇到过什么问题以及是怎么
   解决的（或者还没解决）、目前大概进展到哪一步。
2. 用梳理出的内容，按上面的标准结构，生成一份初始版
   `progress.md`，相当于把之前"欠的账"一次性补上。
3. 补录完成后告诉我一句"已根据历史记录补全了 XX 的进展记录"，
   方便我知道发生了这件事、也可以顺手检查一下补录得准不准确。
4. 之后这个文件夹就按正常的"关键节点更新"策略走，不用每次都重新
   翻历史记录。
"@
    Add-Content -Path $claudeMdPath -Value $progressStrategy
    Write-Host "已添加任务进度记录策略到 CLAUDE.md" -ForegroundColor Green
} else {
    Write-Host "任务进度记录策略已存在，跳过" -ForegroundColor DarkGray
}

# --- 5. 创建桌面快捷方式 ---
$desktopPath = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktopPath "Claude Code 应急启动.lnk"

$shell = New-Object -ComObject WScript.Shell
if (Test-Path $shortcutPath) {
    $existingShortcut = $shell.CreateShortcut($shortcutPath)
    if ($existingShortcut.WorkingDirectory -ne $ProjectFolder) {
        Write-Host "桌面快捷方式目标目录已更新: $ProjectFolder" -ForegroundColor Yellow
        $existingShortcut.WorkingDirectory = $ProjectFolder
        $existingShortcut.Save()
    } else {
        Write-Host "桌面快捷方式已是最新，跳过" -ForegroundColor DarkGray
    }
} else {
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "pwsh.exe"
    $shortcut.Arguments = "-NoExit -File `"$emergencyScriptPath`""
    $shortcut.WorkingDirectory = $ProjectFolder
    $shortcut.IconLocation = "pwsh.exe"
    $shortcut.Save()
    Write-Host "已创建桌面快捷方式" -ForegroundColor Green
}

# --- 6. 配置开机自启（可选）---
$startupFolder = [Environment]::GetFolderPath('Startup')
$startupScriptPath = Join-Path $startupFolder "start-claude.ps1"

$startupScriptContent = @"
# 开机自启 Claude Code
`$claudeReal = Get-Command claude -All -ErrorAction SilentlyContinue |
    Where-Object { `$_.CommandType -ne 'Function' } |
    Select-Object -First 1 -ExpandProperty Source

if (`$claudeReal) {
    Start-Process -FilePath `$claudeReal -ArgumentList "--resume" -WorkingDirectory "$ProjectFolder"
}
"@

if ($EnableAutoStart) {
    if (Test-Path $startupScriptPath) {
        $existingContent = Get-Content $startupScriptPath -Raw
        if ($existingContent -ne $startupScriptContent) {
            Write-Host "开机自启脚本已更新 (项目目录: $ProjectFolder)" -ForegroundColor Yellow
            Set-Content -Path $startupScriptPath -Value $startupScriptContent
        } else {
            Write-Host "开机自启脚本已是最新，跳过" -ForegroundColor DarkGray
        }
    } else {
        Set-Content -Path $startupScriptPath -Value $startupScriptContent
        Write-Host "已创建开机自启脚本" -ForegroundColor Green
    }
} else {
    if (Test-Path $startupScriptPath) {
        Remove-Item -Path $startupScriptPath -Force
        Write-Host "已移除开机自启脚本 (已禁用)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "部署完成！" -ForegroundColor Cyan
Write-Host ""
Write-Host "本次配置内容：" -ForegroundColor Yellow
Write-Host "  - 项目目录: $ProjectFolder"
Write-Host "  - Profile 路径: $ProfilePath"
Write-Host "  - 开机自启: $(if ($EnableAutoStart) { '启用' } else { '禁用' })"
Write-Host "  - 通知模式: $NotifyMode"
Write-Host ""
Write-Host "请重新打开终端使配置生效。" -ForegroundColor DarkGray
