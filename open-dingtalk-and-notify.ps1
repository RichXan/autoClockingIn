param(
    [string] $ConfigPath = (Join-Path $PSScriptRoot "config.local.json")
)

$ErrorActionPreference = "Stop"

function Read-Config {
    param(
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $examplePath = Join-Path $PSScriptRoot "config.example.json"
        throw "Config file not found: $Path. Copy config.example.json to config.local.json and edit it first. Example: $examplePath"
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

function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $AdbArgs
    )

    & $script:AdbPath @AdbArgs
    if ($LASTEXITCODE -ne 0) {
        throw "adb command failed: $($AdbArgs -join ' ')"
    }
}

function Send-BarkNotification {
    param(
        [string] $Title,
        [string] $Body,
        [string] $Icon
    )

    $encodedTitle = [uri]::EscapeDataString($Title)
    $encodedBody = [uri]::EscapeDataString($Body)
    $url = "$script:BarkBaseUrl$encodedTitle/$encodedBody"

    if (-not [string]::IsNullOrWhiteSpace($Icon)) {
        $encodedIcon = [uri]::EscapeDataString($Icon)
        $url = "${url}?icon=$encodedIcon"
    }

    Invoke-RestMethod -Uri $url -Method Get | Out-Null
}

function Turn-OffPhoneScreen {
    if (-not $script:ScreenOffAfterNotification) {
        return
    }

    try {
        Invoke-Adb -AdbArgs @("shell", "input", "keyevent", "POWER")
    } catch {
        Write-Warning "Failed to turn off phone screen: $($_.Exception.Message)"
    }
}

function Start-DingTalk {
    if (-not (Test-Path -LiteralPath $script:AdbPath)) {
        throw "adb.exe not found: $script:AdbPath"
    }

    $devices = & $script:AdbPath devices
    $authorizedDevices = @($devices | Select-String -Pattern "\bdevice\b")
    if ($authorizedDevices.Count -eq 0) {
        throw "No authorized Android device found. Check USB debugging and run: adb devices"
    }

    Invoke-Adb -AdbArgs @("shell", "input", "keyevent", "WAKEUP")
    Start-Sleep -Seconds $script:WakeDelaySeconds

    Invoke-Adb -AdbArgs @(
        "shell", "input", "swipe",
        $script:Swipe.StartX,
        $script:Swipe.StartY,
        $script:Swipe.EndX,
        $script:Swipe.EndY,
        $script:Swipe.DurationMs
    )
    Start-Sleep -Seconds $script:SwipeDelaySeconds

    foreach ($digit in $script:PinDigits) {
        Invoke-Adb -AdbArgs @("shell", "input", "keyevent", "KEYCODE_$digit")
    }
    Invoke-Adb -AdbArgs @("shell", "input", "keyevent", "ENTER")
    Start-Sleep -Seconds $script:UnlockDelaySeconds

    Invoke-Adb -AdbArgs @("shell", "monkey", "-p", $script:DingTalkPackage, "-c", "android.intent.category.LAUNCHER", "1")
    Start-Sleep -Seconds $script:LaunchDelaySeconds

    $focus = & $script:AdbPath shell dumpsys window
    if ($focus -notmatch [regex]::Escape($script:DingTalkPackage)) {
        throw "DingTalk launch was not confirmed in the foreground window."
    }
}

$config = Read-Config -Path $ConfigPath

Assert-ConfigValue $config.adbPath "adbPath"
Assert-ConfigValue $config.dingTalkPackage "dingTalkPackage"
Assert-ConfigValue $config.bark.baseUrl "bark.baseUrl"
Assert-ConfigValue $config.bark.successTitle "bark.successTitle"
Assert-ConfigValue $config.bark.successBody "bark.successBody"
Assert-ConfigValue $config.bark.failureTitle "bark.failureTitle"
Assert-ConfigValue $config.bark.failureBodyPrefix "bark.failureBodyPrefix"
Assert-ConfigValue $config.swipe.startX "swipe.startX"
Assert-ConfigValue $config.swipe.startY "swipe.startY"
Assert-ConfigValue $config.swipe.endX "swipe.endX"
Assert-ConfigValue $config.swipe.endY "swipe.endY"
Assert-ConfigValue $config.swipe.durationMs "swipe.durationMs"

$script:AdbPath = $config.adbPath
$script:PinDigits = @($config.pinDigits)
$script:DingTalkPackage = $config.dingTalkPackage
$script:BarkBaseUrl = $config.bark.baseUrl
$script:SuccessTitle = $config.bark.successTitle
$script:SuccessBody = $config.bark.successBody
$script:FailureTitle = $config.bark.failureTitle
$script:FailureBodyPrefix = $config.bark.failureBodyPrefix
$script:IconUrl = $config.bark.iconUrl
$script:Swipe = $config.swipe
$script:ScreenOffAfterNotification = if ($null -eq $config.screenOffAfterNotification) { $true } else { [bool] $config.screenOffAfterNotification }
$script:WakeDelaySeconds = if ($null -eq $config.timings.wakeDelaySeconds) { 1 } else { [int] $config.timings.wakeDelaySeconds }
$script:SwipeDelaySeconds = if ($null -eq $config.timings.swipeDelaySeconds) { 1 } else { [int] $config.timings.swipeDelaySeconds }
$script:UnlockDelaySeconds = if ($null -eq $config.timings.unlockDelaySeconds) { 2 } else { [int] $config.timings.unlockDelaySeconds }
$script:LaunchDelaySeconds = if ($null -eq $config.timings.launchDelaySeconds) { 3 } else { [int] $config.timings.launchDelaySeconds }

if ($script:PinDigits.Count -eq 0) {
    throw "Missing required config value: pinDigits"
}

try {
    Start-DingTalk
    Send-BarkNotification -Title $script:SuccessTitle -Body $script:SuccessBody -Icon $script:IconUrl
    Turn-OffPhoneScreen
    Write-Host "DingTalk opened successfully. Bark notification sent."
} catch {
    $failureBody = "$script:FailureBodyPrefix$($_.Exception.Message)"
    try {
        Send-BarkNotification -Title $script:FailureTitle -Body $failureBody -Icon $script:IconUrl
        Turn-OffPhoneScreen
        Write-Host "DingTalk launch failed. Bark failure notification sent."
    } catch {
        Write-Warning "Failed to send Bark failure notification: $($_.Exception.Message)"
    }
    throw
}
