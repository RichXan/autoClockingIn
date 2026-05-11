# Windows 自动打开钉钉

这是一个面向 Windows 的小型自动化项目：到达计划时间后，通过 ADB 控制安卓手机亮屏、解锁并打开钉钉。脚本会验证钉钉是否处于前台，然后通过 Bark 发送成功或失败通知，最后可选地让手机息屏。

项目只负责“自动打开钉钉”和“发送打开结果通知”，不执行最终打卡确认动作。

## 功能

- 使用 ADB 唤醒安卓手机。
- 按配置执行上滑解锁。
- 按配置输入 PIN。
- 打开指定安卓应用包名，默认是钉钉 `com.alibaba.android.rimet`。
- 验证当前前台窗口是否为目标应用。
- 使用 Bark 推送成功或失败通知。
- 通知后可选息屏。
- 支持 Windows 任务计划程序定时执行。
- 支持 `08:45` 到 `08:50` 这类随机执行窗口。
- 敏感信息放在本地配置文件中，不提交到 GitHub。

## 项目结构

```text
.
├── open-dingtalk-and-notify.ps1   # 主脚本：控制手机、打开钉钉、发送通知
├── install-scheduled-task.ps1     # 安装或更新 Windows 任务计划
├── config.example.json            # 示例配置，可提交到 GitHub
├── config.local.json              # 本机私有配置，已被 .gitignore 忽略
├── tests/
│   └── validate-project.ps1       # 项目结构和配置验证脚本
├── .gitignore
├── DING.md
└── README.md
```

## 快速开始

1. 安装 ADB，并确认 `adb.exe` 路径。
2. 手机开启开发者选项和 USB 调试。
3. 用 USB 连接手机，并在手机上允许 USB 调试。
4. 复制配置文件：

```powershell
Copy-Item .\config.example.json .\config.local.json
```

5. 修改 `config.local.json`，填入本机真实配置。
6. 手动运行一次主脚本验证：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\open-dingtalk-and-notify.ps1"
```

7. 安装或更新 Windows 定时任务：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\install-scheduled-task.ps1"
```

## 配置文件

真实配置写在 `config.local.json`。这个文件包含 PIN、Bark 地址等敏感信息，已经被 `.gitignore` 忽略，不要提交到 GitHub。

仓库中只提交 `config.example.json`：

```json
{
  "adbPath": "D:\\ProgramFile\\platform-tools\\adb.exe",
  "pinDigits": [1, 2, 3, 4, 5, 6],
  "dingTalkPackage": "com.alibaba.android.rimet",
  "screenOffAfterNotification": true,
  "swipe": {
    "startX": 630,
    "startY": 2700,
    "endX": 630,
    "endY": 150,
    "durationMs": 800
  },
  "timings": {
    "wakeDelaySeconds": 1,
    "swipeDelaySeconds": 1,
    "unlockDelaySeconds": 2,
    "launchDelaySeconds": 3
  },
  "bark": {
    "baseUrl": "https://bark.example.com/your-device-key/",
    "successTitle": "钉钉已启动",
    "successBody": "已亮屏、解锁并启动钉钉。",
    "failureTitle": "钉钉启动失败",
    "failureBodyPrefix": "失败原因：",
    "iconUrl": "https://play-lh.googleusercontent.com/J93kHXLNdp9pIwH4SKWUoqxr-EUaRh7QAPo5E3Zj1BEbRi_gfLLT2xN-lsSklpiDUSQ8=w240-h480"
  },
  "schedule": {
    "taskName": "OpenDingTalkAndNotifyRandomMorning",
    "startTime": "08:45",
    "randomDelayMinutes": 5
  }
}
```

### 常用配置说明

- `adbPath`：`adb.exe` 的完整路径。
- `pinDigits`：手机 PIN 数字数组，例如 `[1, 2, 3, 4, 5, 6]`。
- `dingTalkPackage`：目标应用包名，钉钉通常是 `com.alibaba.android.rimet`。
- `screenOffAfterNotification`：发送通知后是否息屏。
- `swipe`：解锁上滑坐标，当前示例适合 `1260x2800` 分辨率。
- `timings`：每个步骤之间的等待时间。
- `bark.baseUrl`：Bark 推送基础地址，建议以 `/` 结尾。
- `schedule.startTime`：Windows 任务计划开始触发时间。
- `schedule.randomDelayMinutes`：随机延迟分钟数。

## 手动运行

在项目目录中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\open-dingtalk-and-notify.ps1"
```

也可以显式指定配置文件：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\open-dingtalk-and-notify.ps1" -ConfigPath ".\config.local.json"
```

## Windows 定时任务

定时任务不是写在主脚本里的，而是配置在 Windows 的“任务计划程序”中。

关系是：

```text
Windows 任务计划程序
  ↓ 到时间触发
open-dingtalk-and-notify.ps1
  ↓ 执行具体动作
ADB 控制手机 + Bark 通知 + 手机息屏
```

安装或更新任务计划：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\install-scheduled-task.ps1"
```

安装脚本会读取 `config.local.json` 中的：

- `schedule.taskName`
- `schedule.startTime`
- `schedule.randomDelayMinutes`

如果配置为：

```json
"schedule": {
  "taskName": "OpenDingTalkAndNotifyRandomMorning",
  "startTime": "08:45",
  "randomDelayMinutes": 5
}
```

实际执行窗口就是每天 `08:45` 到 `08:50` 之间随机执行。

## 检查任务计划

查看任务是否存在：

```powershell
Get-ScheduledTask -TaskName OpenDingTalkAndNotifyRandomMorning
```

查看触发器和执行动作：

```powershell
$task = Get-ScheduledTask -TaskName OpenDingTalkAndNotifyRandomMorning
$task.Triggers | Select-Object StartBoundary, RandomDelay, Enabled
$task.Actions | Select-Object Execute, Arguments
```

查看最近一次运行结果：

```powershell
Get-ScheduledTaskInfo -TaskName OpenDingTalkAndNotifyRandomMorning
```

常见 `LastTaskResult`：

- `0`：任务执行成功退出。
- 非 `0`：任务失败或被中断，需要检查 ADB、配置文件或 Bark 失败通知。

手动触发一次任务：

```powershell
Start-ScheduledTask -TaskName OpenDingTalkAndNotifyRandomMorning
```

禁用任务：

```powershell
Disable-ScheduledTask -TaskName OpenDingTalkAndNotifyRandomMorning
```

重新启用任务：

```powershell
Enable-ScheduledTask -TaskName OpenDingTalkAndNotifyRandomMorning
```

删除任务：

```powershell
Unregister-ScheduledTask -TaskName OpenDingTalkAndNotifyRandomMorning -Confirm:$false
```

## 检查 ADB

```powershell
D:\ProgramFile\platform-tools\adb.exe devices -l
```

正常状态应包含：

```text
device
```

如果显示 `unauthorized`，需要解锁手机，并在手机上允许 USB 调试。

## 验证项目

提交前建议运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tests\validate-project.ps1"
```

验证内容包括：

- 主脚本和安装脚本语法。
- 示例配置是否存在且字段完整。
- 主脚本是否读取 JSON 配置。
- 主脚本中是否误写入私有 Bark token 或 PIN。
- `.gitignore` 是否忽略 `config.local.json`。

## 常见问题

### 上滑后没有进入密码页

调整 `config.local.json` 中的 `swipe`：

- `startY` 改得更接近屏幕底部。
- `endY` 改得更接近屏幕顶部。
- `durationMs` 适当增加。

### 钉钉没有打开

确认钉钉包名是否仍为：

```text
com.alibaba.android.rimet
```

手动打开钉钉后可检查当前前台窗口：

```powershell
D:\ProgramFile\platform-tools\adb.exe shell dumpsys window | Select-String -Pattern "mCurrentFocus|mFocusedApp"
```

### 没收到 Bark 推送

检查：

- `bark.baseUrl` 是否正确。
- 电脑网络是否能访问 Bark 服务。
- `bark.iconUrl` 是否仍然是公网可访问图片。

## 安全提醒

- 不要提交 `config.local.json`。
- 不要把真实 PIN、Bark key、设备信息写进 README 或示例配置。
- 如果已经误提交敏感信息，需要先更换对应密钥或密码，再清理 Git 历史。
