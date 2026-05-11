# ADB 常用命令

这些命令仅作为调试参考，不包含真实 PIN。

```powershell
adb shell input keyevent WAKEUP
adb shell input swipe 630 2700 630 150 800
adb shell input keyevent KEYCODE_1
adb shell input keyevent ENTER
adb shell monkey -p com.alibaba.android.rimet -c android.intent.category.LAUNCHER 1
```

查看当前前台应用：

```powershell
adb shell dumpsys window | Select-String -Pattern "mCurrentFocus|mFocusedApp"
```
