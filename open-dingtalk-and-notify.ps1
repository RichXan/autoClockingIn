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

function Initialize-Config {
    param(
        $Config
    )

    $script:BarkBaseUrl = $Config.bark.baseUrl
    $script:SuccessTitle = $Config.bark.successTitle
    $script:SuccessBody = $Config.bark.successBody
    $script:FailureTitle = $Config.bark.failureTitle
    $script:FailureBodyPrefix = $Config.bark.failureBodyPrefix
    $script:IconUrl = $Config.bark.iconUrl

    Assert-ConfigValue $Config.adbPath "adbPath"
    Assert-ConfigValue $Config.dingTalkPackage "dingTalkPackage"
    Assert-ConfigValue $Config.bark.baseUrl "bark.baseUrl"
    Assert-ConfigValue $Config.bark.successTitle "bark.successTitle"
    Assert-ConfigValue $Config.bark.successBody "bark.successBody"
    Assert-ConfigValue $Config.bark.failureTitle "bark.failureTitle"
    Assert-ConfigValue $Config.bark.failureBodyPrefix "bark.failureBodyPrefix"
    Assert-ConfigValue $Config.swipe.startX "swipe.startX"
    Assert-ConfigValue $Config.swipe.startY "swipe.startY"
    Assert-ConfigValue $Config.swipe.endX "swipe.endX"
    Assert-ConfigValue $Config.swipe.endY "swipe.endY"
    Assert-ConfigValue $Config.swipe.durationMs "swipe.durationMs"

    $script:AdbPath = $Config.adbPath
    $script:PinDigits = @($Config.pinDigits)
    $script:DingTalkPackage = $Config.dingTalkPackage
    $script:Swipe = $Config.swipe
    $script:ScreenOffAfterNotification = if ($null -eq $Config.screenOffAfterNotification) { $true } else { [bool] $Config.screenOffAfterNotification }
    $script:WakeDelaySeconds = if ($null -eq $Config.timings.wakeDelaySeconds) { 1 } else { [int] $Config.timings.wakeDelaySeconds }
    $script:SwipeDelaySeconds = if ($null -eq $Config.timings.swipeDelaySeconds) { 1 } else { [int] $Config.timings.swipeDelaySeconds }
    $script:UnlockDelaySeconds = if ($null -eq $Config.timings.unlockDelaySeconds) { 2 } else { [int] $Config.timings.unlockDelaySeconds }
    $script:LaunchDelaySeconds = if ($null -eq $Config.timings.launchDelaySeconds) { 3 } else { [int] $Config.timings.launchDelaySeconds }

    if ($script:PinDigits.Count -eq 0) {
        throw "Missing required config value: pinDigits"
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
    $isDingTalkForeground = [bool] ($focus | Select-String -Pattern ([regex]::Escape($script:DingTalkPackage)) -Quiet)
    if (-not $isDingTalkForeground) {
        throw "DingTalk launch was not confirmed in the foreground window."
    }
}

try {
    $config = Read-Config -Path $ConfigPath
    Initialize-Config -Config $config
    Start-DingTalk
    Send-BarkNotification -Title $script:SuccessTitle -Body $script:SuccessBody -Icon $script:IconUrl
    Turn-OffPhoneScreen
    Write-Host "DingTalk opened successfully. Bark notification sent."
} catch {
    $failureBody = "$script:FailureBodyPrefix$($_.Exception.Message)"
    try {
        if (-not [string]::IsNullOrWhiteSpace($script:BarkBaseUrl)) {
            Send-BarkNotification -Title $script:FailureTitle -Body $failureBody -Icon $script:IconUrl
            Turn-OffPhoneScreen
            Write-Host "DingTalk launch failed. Bark failure notification sent."
        } else {
            Write-Warning "Bark base URL is unavailable; failure notification cannot be sent."
        }
    } catch {
        Write-Warning "Failed to send Bark failure notification: $($_.Exception.Message)"
    }
    throw
}
