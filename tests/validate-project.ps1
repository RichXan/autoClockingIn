$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ScriptPath = Join-Path $ProjectRoot "open-dingtalk-and-notify.ps1"
$InstallTaskPath = Join-Path $ProjectRoot "install-scheduled-task.ps1"
$ExampleConfigPath = Join-Path $ProjectRoot "config.example.json"
$GitIgnorePath = Join-Path $ProjectRoot ".gitignore"

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $ScriptPath) "Missing open-dingtalk-and-notify.ps1"
Assert-True (Test-Path -LiteralPath $InstallTaskPath) "Missing install-scheduled-task.ps1"
Assert-True (Test-Path -LiteralPath $ExampleConfigPath) "Missing config.example.json"
Assert-True (Test-Path -LiteralPath $GitIgnorePath) "Missing .gitignore"

foreach ($path in @($ScriptPath, $InstallTaskPath)) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref] $tokens, [ref] $errors) | Out-Null
    Assert-True ($errors.Count -eq 0) "PowerShell script has syntax errors in $path`: $($errors | Out-String)"
}

$scriptText = Get-Content -LiteralPath $ScriptPath -Raw
Assert-True ($scriptText -match "ConvertFrom-Json") "Main script should read JSON configuration"
Assert-True ($scriptText -match "ConfigPath") "Main script should expose a configurable ConfigPath"
Assert-True ($scriptText -notmatch "mqTBZNJR5LauL4pSq5izF4") "Main script must not contain the private Bark token"
Assert-True ($scriptText -notmatch "979979") "Main script must not contain the private phone PIN"

$installTaskText = Get-Content -LiteralPath $InstallTaskPath -Raw
Assert-True ($installTaskText -match "Register-ScheduledTask") "Install script should register a Windows scheduled task"
Assert-True ($installTaskText -match "RandomDelay") "Install script should configure random delay from config"
Assert-True ($installTaskText -match "ConvertFrom-Json") "Install script should read JSON configuration"

$exampleConfig = Get-Content -LiteralPath $ExampleConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($null -ne $exampleConfig.adbPath) "Example config missing adbPath"
Assert-True ($null -ne $exampleConfig.pinDigits) "Example config missing pinDigits"
Assert-True ($null -ne $exampleConfig.dingTalkPackage) "Example config missing dingTalkPackage"
Assert-True ($null -ne $exampleConfig.bark.baseUrl) "Example config missing bark.baseUrl"
Assert-True ($null -ne $exampleConfig.swipe.startX) "Example config missing swipe.startX"
Assert-True ($null -ne $exampleConfig.schedule.taskName) "Example config missing schedule.taskName"

$gitIgnore = Get-Content -LiteralPath $GitIgnorePath -Raw
Assert-True ($gitIgnore -match "config\.local\.json") ".gitignore should ignore config.local.json"

Write-Host "Project validation passed."
