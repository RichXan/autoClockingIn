param(
    [string] $ConfigPath = (Join-Path $PSScriptRoot "config.local.json")
)

$ErrorActionPreference = "Stop"

function Read-Config {
    param(
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }

    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Assert-ConfigValue {
    param(
        $Value,
        [string] $Name
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string] $Value)) {
        throw "Missing required config value: $Name"
    }
}

$config = Read-Config -Path $ConfigPath

Assert-ConfigValue $config.schedule.taskName "schedule.taskName"
Assert-ConfigValue $config.schedule.startTime "schedule.startTime"
Assert-ConfigValue $config.schedule.randomDelayMinutes "schedule.randomDelayMinutes"

$taskName = $config.schedule.taskName
$startTime = $config.schedule.startTime
$randomDelayMinutes = [int] $config.schedule.randomDelayMinutes
$mainScript = Join-Path $PSScriptRoot "open-dingtalk-and-notify.ps1"

if (-not (Test-Path -LiteralPath $mainScript)) {
    throw "Main script not found: $mainScript"
}

$actionArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$mainScript`" -ConfigPath `"$ConfigPath`""
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs
$trigger = New-ScheduledTaskTrigger -Daily -At $startTime
$trigger.RandomDelay = "PT${randomDelayMinutes}M"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Open DingTalk on Android via ADB, then send Bark notification." `
    -Force | Out-Null

Write-Host "Scheduled task installed or updated: $taskName"
