#!/bin/bash
# Battery/charging state for Bluetooth and 2.4GHz wireless peripherals.
#
# Prefers the full python3 collector (Bluetooth via BlueZ, sysfs hidpp
# batteries, upower supplement, Razer via openrazer). When python3 is not
# available a minimal bash fallback reads sysfs power-supply batteries and
# parses `bluetoothctl info` battery lines instead. Both emit the same JSON
# document shape expected by DeviceBattery.js.
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT=${DEVICEBATT_TIMEOUT:-5}

if command -v python3 >/dev/null 2>&1; then
  exec python3 "$SCRIPT_DIR/device-battery.py"
fi

emit() {
  # emit <source> <id> <name> <icon> <kind> <connected> <percent> <charging> <state>
  local source="$1" id="$2" name="$3" icon="$4" kind="$5"
  local connected="$6" percent="$7" charging="$8" state="$9"
  printf '{"source":"%s","id":"%s","name":"%s","icon":%s,"kind":%s,"connected":%s,"percent":%s,"charging":%s,"state":%s}'
    "$source" "$id" "$name" \
    "$([ "$icon" = "null" ] && echo null || printf '"%s"' "$icon")" \
    "$([ "$kind" = "null" ] && echo null || printf '"%s"' "$kind")" \
    "$connected" "$percent" "$charging" \
    "$([ "$state" = "null" ] && echo null || printf '"%s"' "$state")"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

bluetooth="false"
sysfs="false"
upower="false"
razer="false"
devices=""
first=1

append_dev() {
  local entry
  entry="$(emit "$@")"
  if [ "$first" = "1" ]; then
    devices="$entry"
    first=0
  else
    devices="$devices,$entry"
  fi
}

# --- sysfs power-supply scan ------------------------------------------------
if [ -d /sys/class/power_supply ]; then
  for dir in /sys/class/power_supply/*/; do
    [ -e "$dir/type" ] || continue
    type="$(cat "$dir/type" 2>/dev/null || echo "")"
    [ "$type" = "Battery" ] || [ "$type" = "USB" ] || continue
    scope="$(cat "$dir/scope" 2>/dev/null || echo "")"
    if [ "$scope" = "System" ] && [ "${DEVICEBATT_INCLUDE_SYSTEM:-0}" != "1" ]; then
      continue
    fi
    id="$(basename "$dir")"
    model="$(cat "$dir/model_name" 2>/dev/null || echo "")"
    if [ "$type" = "USB" ] && [ -z "$model" ]; then continue; fi
    name="${model:-$id}"
    capacity="$(cat "$dir/capacity" 2>/dev/null || echo "")"
    status="$(cat "$dir/status" 2>/dev/null || echo "")"
    present="$(cat "$dir/present" 2>/dev/null || echo 1)"
    [ "$present" = "1" ] && connected="true" || connected="false"
    [ -n "$capacity" ] || capacity="null"
    if [ -n "$status" ]; then
      [ "$status" = "Charging" ] && charging="true" || charging="false"
      state="\"$(json_escape "$status")\""
    else
      charging="null"
      state="null"
    fi
    case "$name" in
      *[Kk]eyboard*|[Kk]eypad*) kind="keyboard" ;;
      *[Mm]ouse*|*[Tt]rackball*) kind="mouse" ;;
      *[Hh]eadset*|*[Hh]eadphone*|*[Ee]arbud*|*[Aa]irpods*) kind="headset" ;;
      *) kind="other" ;;
    esac
    append_dev sysfs "$id" "$(json_escape "$name")" null "$kind" "$connected" "$capacity" "$charging" "$state"
    sysfs="true"
  done
fi

# --- bluetooth via bluetoothctl (python fallback) ---------------------------
if command -v bluetoothctl >/dev/null 2>&1; then
  devices_out="$(timeout "$TIMEOUT" bluetoothctl devices 2>/dev/null || true)"
  while IFS= read -r line; do
    addr="$(echo "$line" | awk '{print $2}')"
    [ -z "$addr" ] && continue
    info="$(timeout "$TIMEOUT" bluetoothctl info "$addr" 2>/dev/null || true)"
    name="$(echo "$info" | sed -n 's/^[[:space:]]*Name:[[:space:]]*//p' | head -1)"
    connected="$(echo "$info" | sed -n 's/^[[:space:]]*Connected:[[:space:]]*//p' | head -1)"
    [ "$connected" = "yes" ] && conn="true" || conn="false"
    batt="$(echo "$info" | sed -n 's/.*Battery Percentage:.*(\([0-9][0-9]*\))/\1/p' | head -1)"
    [ -n "$batt" ] || batt="null"
    [ -n "$name" ] || name="$addr"
    append_dev bluetooth "$(echo "$addr" | tr 'A-F' 'a-f')" "$(json_escape "$name")" null null "$conn" "$batt" null null
    bluetooth="true"
  done <<< "$devices_out"
fi

cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ok": true,
  "sources": {
    "bluetooth": $bluetooth,
    "sysfs": $sysfs,
    "upower": $upower,
    "razer": $razer
  },
  "devices": [${devices:-}]
}
EOF
