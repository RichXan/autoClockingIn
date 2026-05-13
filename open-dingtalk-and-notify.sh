#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${1:-"$SCRIPT_DIR/config.local.json"}"

ADB_PATH=""
DINGTALK_PACKAGE=""
BARK_BASE_URL=""
SUCCESS_TITLE=""
SUCCESS_BODY=""
FAILURE_TITLE=""
FAILURE_BODY_PREFIX=""
ICON_URL=""
SCREEN_OFF_AFTER_NOTIFICATION="true"
WAKE_DELAY_SECONDS="1"
SWIPE_DELAY_SECONDS="1"
UNLOCK_DELAY_SECONDS="2"
LAUNCH_DELAY_SECONDS="3"
POST_LAUNCH_HOLD_SECONDS="0"
SWIPE_START_X=""
SWIPE_START_Y=""
SWIPE_END_X=""
SWIPE_END_Y=""
SWIPE_DURATION_MS=""
PIN_DIGITS=()

json_get() {
    local path="$1"
    python3 - "$CONFIG_PATH" "$path" <<'PY'
import json
import sys

config_path, dotted_path = sys.argv[1], sys.argv[2]
with open(config_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

value = data
for part in dotted_path.split("."):
    if not isinstance(value, dict) or part not in value:
        sys.exit(2)
    value = value[part]

if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (int, float, str)):
    print(value)
elif value is None:
    sys.exit(2)
else:
    print(json.dumps(value, ensure_ascii=False))
PY
}

json_get_or_default() {
    local path="$1"
    local default_value="$2"

    json_get "$path" 2>/dev/null || printf '%s\n' "$default_value"
}

json_get_array_lines() {
    local path="$1"
    python3 - "$CONFIG_PATH" "$path" <<'PY'
import json
import sys

config_path, dotted_path = sys.argv[1], sys.argv[2]
with open(config_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

value = data
for part in dotted_path.split("."):
    if not isinstance(value, dict) or part not in value:
        sys.exit(2)
    value = value[part]

if not isinstance(value, list):
    sys.exit(2)

for item in value:
    print(item)
PY
}

require_value() {
    local value="$1"
    local name="$2"

    if [[ -z "$value" ]]; then
        fail "Missing required config value: $name"
    fi
}

send_bark_notification() {
    local title="$1"
    local body="$2"
    local icon="$3"
    local url

    url="$(python3 - "$BARK_BASE_URL" "$title" "$body" "$icon" <<'PY'
import sys
from urllib.parse import quote

base_url, title, body, icon = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
url = f"{base_url}{quote(title)}/{quote(body)}"
if icon:
    url = f"{url}?icon={quote(icon, safe='')}"
print(url)
PY
)"

    curl -fsS "$url" >/dev/null
}

run_adb() {
    "$ADB_PATH" "$@"
    local exit_code=$?
    if [[ "$exit_code" -ne 0 ]]; then
        fail "adb command failed: $*"
    fi
}

turn_off_phone_screen() {
    if [[ "$SCREEN_OFF_AFTER_NOTIFICATION" != "true" ]]; then
        return
    fi

    "$ADB_PATH" shell input keyevent POWER >/dev/null 2>&1 || true
}

fail() {
    local message="$1"

    if [[ -n "${BARK_BASE_URL:-}" ]]; then
        send_bark_notification "$FAILURE_TITLE" "${FAILURE_BODY_PREFIX}${message}" "$ICON_URL" \
            && echo "DingTalk launch failed. Bark failure notification sent." \
            || echo "Failed to send Bark failure notification." >&2
        turn_off_phone_screen
    else
        echo "Bark base URL is unavailable; failure notification cannot be sent." >&2
    fi

    echo "$message" >&2
    exit 1
}

load_config() {
    if [[ ! -f "$CONFIG_PATH" ]]; then
        echo "Config file not found: $CONFIG_PATH" >&2
        echo "Copy config.example.json to config.local.json and edit it first." >&2
        exit 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "python3 is required to read JSON config." >&2
        exit 1
    fi

    ADB_PATH="$(json_get adbPath 2>/dev/null || true)"
    DINGTALK_PACKAGE="$(json_get dingTalkPackage 2>/dev/null || true)"
    BARK_BASE_URL="$(json_get bark.baseUrl 2>/dev/null || true)"
    SUCCESS_TITLE="$(json_get bark.successTitle 2>/dev/null || true)"
    SUCCESS_BODY="$(json_get bark.successBody 2>/dev/null || true)"
    FAILURE_TITLE="$(json_get bark.failureTitle 2>/dev/null || true)"
    FAILURE_BODY_PREFIX="$(json_get bark.failureBodyPrefix 2>/dev/null || true)"
    ICON_URL="$(json_get_or_default bark.iconUrl "")"
    SCREEN_OFF_AFTER_NOTIFICATION="$(json_get_or_default screenOffAfterNotification true)"
    WAKE_DELAY_SECONDS="$(json_get_or_default timings.wakeDelaySeconds 1)"
    SWIPE_DELAY_SECONDS="$(json_get_or_default timings.swipeDelaySeconds 1)"
    UNLOCK_DELAY_SECONDS="$(json_get_or_default timings.unlockDelaySeconds 2)"
    LAUNCH_DELAY_SECONDS="$(json_get_or_default timings.launchDelaySeconds 3)"
    POST_LAUNCH_HOLD_SECONDS="$(json_get_or_default timings.postLaunchHoldSeconds 0)"
    SWIPE_START_X="$(json_get swipe.startX 2>/dev/null || true)"
    SWIPE_START_Y="$(json_get swipe.startY 2>/dev/null || true)"
    SWIPE_END_X="$(json_get swipe.endX 2>/dev/null || true)"
    SWIPE_END_Y="$(json_get swipe.endY 2>/dev/null || true)"
    SWIPE_DURATION_MS="$(json_get swipe.durationMs 2>/dev/null || true)"

    PIN_DIGITS=()
    while IFS= read -r digit; do
        PIN_DIGITS+=("$digit")
    done < <(json_get_array_lines pinDigits 2>/dev/null || true)
}

validate_config() {
    require_value "$ADB_PATH" "adbPath"
    require_value "$DINGTALK_PACKAGE" "dingTalkPackage"
    require_value "$BARK_BASE_URL" "bark.baseUrl"
    require_value "$SUCCESS_TITLE" "bark.successTitle"
    require_value "$SUCCESS_BODY" "bark.successBody"
    require_value "$FAILURE_TITLE" "bark.failureTitle"
    require_value "$FAILURE_BODY_PREFIX" "bark.failureBodyPrefix"
    require_value "$SWIPE_START_X" "swipe.startX"
    require_value "$SWIPE_START_Y" "swipe.startY"
    require_value "$SWIPE_END_X" "swipe.endX"
    require_value "$SWIPE_END_Y" "swipe.endY"
    require_value "$SWIPE_DURATION_MS" "swipe.durationMs"

    if [[ "${#PIN_DIGITS[@]}" -eq 0 ]]; then
        fail "Missing required config value: pinDigits"
    fi

    if [[ ! -x "$ADB_PATH" ]]; then
        fail "adb is not executable: $ADB_PATH"
    fi
}

start_dingtalk() {
    if ! "$ADB_PATH" devices | awk 'NR > 1 && $2 == "device" { found = 1 } END { exit found ? 0 : 1 }'; then
        fail "No authorized Android device found. Check USB debugging and run: adb devices"
    fi

    run_adb shell input keyevent WAKEUP
    sleep "$WAKE_DELAY_SECONDS"

    run_adb shell input swipe "$SWIPE_START_X" "$SWIPE_START_Y" "$SWIPE_END_X" "$SWIPE_END_Y" "$SWIPE_DURATION_MS"
    sleep "$SWIPE_DELAY_SECONDS"

    local digit
    for digit in "${PIN_DIGITS[@]}"; do
        run_adb shell input keyevent "KEYCODE_$digit"
    done
    run_adb shell input keyevent ENTER
    sleep "$UNLOCK_DELAY_SECONDS"

    run_adb shell monkey -p "$DINGTALK_PACKAGE" -c android.intent.category.LAUNCHER 1
    sleep "$LAUNCH_DELAY_SECONDS"

    if ! "$ADB_PATH" shell dumpsys window | grep -Fq "$DINGTALK_PACKAGE"; then
        fail "DingTalk launch was not confirmed in the foreground window."
    fi

    if [[ "$POST_LAUNCH_HOLD_SECONDS" -gt 0 ]]; then
        sleep "$POST_LAUNCH_HOLD_SECONDS"
    fi
}

load_config
validate_config
start_dingtalk
send_bark_notification "$SUCCESS_TITLE" "$SUCCESS_BODY" "$ICON_URL"
turn_off_phone_screen
echo "DingTalk opened successfully. Bark notification sent."
