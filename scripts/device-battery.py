#!/usr/bin/env python3
"""Collect battery/charging state for wireless peripherals.

Reads, with graceful degradation per source:
  - Bluetooth devices that expose a battery via BlueZ (org.bluez.Battery1).
    The percentage is read from the BlueZ object manager over DBus with
    `busctl`, so no extra Python DBus bindings are required.
  - 2.4GHz receivers that surface a battery through the kernel's power_supply
    class (Logitech hidpp dongles, etc.) directly from /sys/class/power_supply.
  - The same power-supply tree through `upower`, kept as a supplementary
    source for batteries sysfs reports in a different namespace.
  - Razer wireless peripherals through the python-openrazer daemon client
    (org.razer on the session bus).

Output is a single JSON document on stdout:

  {
    "timestamp": "ISO-8601",
    "ok": true,
    "sources": {"bluetooth": bool, "sysfs": bool, "upower": bool, "razer": bool},
    "devices": [
      {
        "source": "bluetooth" | "sysfs" | "upower" | "razer",
        "id": str,
        "name": str,
        "icon": str|null,      // BlueZ Device1.Icon, e.g. "input-keyboard"
        "kind": str|null,      // normalized peripheral kind
        "address": str|null,   // Bluetooth MAC
        "model": str|null,
        "connected": bool,
        "percent": int|null,   // 0..100, null when unknown
        "charging": bool|null,
        "state": str|null      // "Charging" | "Discharging" | "Full" | ...
      }
    ]
  }

Environment:
  DEVICEBATT_INCLUDE_SYSTEM=1  include System-scope batteries (laptop BAT0).
  DEVICEBATT_TIMEOUT           per-subprocess timeout in seconds (default 5).
"""

import json
import os
import re
import shlex
import subprocess
import sys
import time

TIMEOUT = float(os.environ.get("DEVICEBATT_TIMEOUT", "5"))
INCLUDE_SYSTEM = os.environ.get("DEVICEBATT_INCLUDE_SYSTEM", "0") == "1"

DEVICE_PATH_RE = re.compile(r"^/org/bluez/hci\d+/dev_[0-9A-F_]+$")
BATTERY_CHILD_RE = re.compile(r"^/org/bluez/hci\d+/dev_[0-9A-F_]+/battery\d+$")


def run(args, timeout=TIMEOUT):
    try:
        proc = subprocess.run(
            args, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout
    except Exception:
        return -1, ""


# --------------------------------------------------------------------------
# BlueZ object manager parsing
# --------------------------------------------------------------------------

def parse_busctl_sig(sig, toks, index):
    """Parse one `busctl`-serialized value given its type signature.

    busctl prints the GetManagedObjects reply as a flat token stream where
    every value is prefixed with its DBus signature. Simple types occupy one
    token; containers are a count followed by their entries. Handles the
    subset the BlueZ object tree uses (s, o, y, b, u, n, q, as, ay, a{sv},
    a{sa{sv}}, a{oa{sa{sv}}}).
    """
    s = sig[0]
    if s == "a":
        inner = sig[1:]
        if inner.startswith("{"):
            # a{...} dict. In the BlueZ object tree dict keys are always a
            # single basic type ('o' for paths, 's' for interface/property
            # names), so the key signature is one char and the rest is the
            # value signature.
            key_sig = inner[1]
            val_sig = inner[2:-1]
            count = int(toks[index])
            index += 1
            result = {}
            for _ in range(count):
                key, index = parse_busctl_sig(key_sig, toks, index)
                value, index = parse_busctl_sig(val_sig, toks, index)
                result[key] = value
            return result, index
        count = int(toks[index])
        index += 1
        result = []
        for _ in range(count):
            value, index = parse_busctl_sig(inner, toks, index)
            result.append(value)
        return result, index
    if s == "v":
        # Variants print the actual value signature followed by the value.
        inner_sig = toks[index]
        return parse_busctl_sig(inner_sig, toks, index + 1)
    # Simple types serialize to a single token.
    return toks[index], index + 1


def bluez_objects():
    """Return {object_path: {interface: {property: value}}} or None."""
    rc, out = run(["busctl", "--system", "call", "org.bluez", "/",
                   "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"])
    if rc != 0 or not out.strip():
        return None
    toks = shlex.split(out)
    if not toks:
        return None
    sig = toks[0]
    if not sig.startswith("a{"):
        return None
    try:
        objects, _ = parse_busctl_sig(sig, toks, 1)
    except (ValueError, IndexError):
        return None
    return objects if isinstance(objects, dict) else None


def _int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _bool(value):
    return str(value).lower() == "true"


def collect_bluetooth(objects):
    if not objects:
        return [], False
    devices = []
    for path, ifaces in objects.items():
        if not DEVICE_PATH_RE.match(path):
            continue
        dev = ifaces.get("org.bluez.Device1", {})
        address = dev.get("Address")
        if not address:
            continue
        levels = []
        for battery_path in sorted(objects):
            if not battery_path.startswith(path + "/battery"):
                continue
            battery = objects[battery_path].get("org.bluez.Battery1", {})
            percent = _int(battery.get("Percentage"))
            level = battery.get("Level")
            if percent is not None:
                levels.append({"path": battery_path,
                               "percent": percent,
                               "level": level})
        # Some stacks publish Battery1 on the device object itself.
        if not levels:
            battery = ifaces.get("org.bluez.Battery1", {})
            percent = _int(battery.get("Percentage"))
            if percent is not None:
                levels.append({"path": path,
                               "percent": percent,
                               "level": battery.get("Level")})
        name = dev.get("Name") or dev.get("Alias") or address
        icon = dev.get("Icon")
        devices.append({
            "source": "bluetooth",
            "id": address.lower(),
            "name": name,
            "icon": icon or None,
            "kind": bluez_icon_kind(icon) if icon else None,
            "address": address,
            "model": None,
            "connected": _bool(dev.get("Connected")),
            "paired": _bool(dev.get("Paired")),
            "percent": levels[0]["percent"] if levels else None,
            "charging": None,
            "state": None,
            "batteryLevels": levels,
        })
    return devices, True


def bluez_icon_kind(icon):
    icon = str(icon or "").lower()
    if "keyboard" in icon:
        return "keyboard"
    if "mouse" in icon:
        return "mouse"
    if "audio" in icon or "headset" in icon:
        return "headset"
    if "gaming" in icon:
        return "gamepad"
    if "tablet" in icon:
        return "tablet"
    if "phone" in icon or "smartphone" in icon:
        return "phone"
    if "watch" in icon:
        return "watch"
    if "computer" in icon or "laptop" in icon:
        return "computer"
    return "other"


# --------------------------------------------------------------------------
# sysfs power_supply scan
# --------------------------------------------------------------------------

SYSFS_DIR = "/sys/class/power_supply"


def _read_sysfs(path, name):
    try:
        with open(os.path.join(path, name), "r", encoding="utf-8",
                  errors="replace") as handle:
            return handle.read().strip()
    except OSError:
        return None


def collect_sysfs():
    devices = []
    if not os.path.isdir(SYSFS_DIR):
        return [], False
    try:
        entries = os.listdir(SYSFS_DIR)
    except OSError:
        return [], False
    for entry in sorted(entries):
        path = os.path.join(SYSFS_DIR, entry)
        if not os.path.isdir(path):
            continue
        battery_type = _read_sysfs(path, "type")
        if battery_type not in ("Battery", "USB"):
            continue
        scope = _read_sysfs(path, "scope")
        if scope == "System" and not INCLUDE_SYSTEM:
            continue
        model = _read_sysfs(path, "model_name") or None
        capacity = _int(_read_sysfs(path, "capacity"))
        capacity_level = _read_sysfs(path, "capacity_level") or None
        status = _read_sysfs(path, "status") or None
        present = (_read_sysfs(path, "present") or "1") == "1"
        if battery_type == "USB" and not model:
            continue
        name = model or entry
        devices.append({
            "source": "sysfs",
            "id": entry,
            "name": name,
            "icon": None,
            "kind": kind_from_name(name),
            "address": None,
            "model": model,
            "connected": present,
            "percent": capacity if capacity is not None else None,
            "charging": status == "Charging",
            "state": status,
            "batteryLevels": None,
        })
    return devices, True


def kind_from_name(name):
    name = str(name or "").lower()
    if "keyboard" in name or "keypad" in name:
        return "keyboard"
    if "mouse" in name or "trackball" in name:
        return "mouse"
    if "headset" in name or "headphone" in name or "earbud" in name or "airpods" in name:
        return "headset"
    if "gamepad" in name or "controller" in name:
        return "gamepad"
    if "tablet" in name:
        return "tablet"
    if "watch" in name:
        return "watch"
    if "laptop" in name or "computer" in name:
        return "computer"
    if "speaker" in name:
        return "speaker"
    return "other"


# --------------------------------------------------------------------------
# upower supplement
# --------------------------------------------------------------------------

UPOWER_DEVICE_RE = re.compile(r"^/org/freedesktop/UPower/devices/(.+)$")


def collect_upower(existing_ids, bluetooth_devices=None):
    devices = []
    bluetooth_devices = bluetooth_devices or []
    bt_names = {str(device.get("name", "")).lower() for device in bluetooth_devices}
    bt_addresses = {str(device.get("address", "")).lower()
                    for device in bluetooth_devices}
    rc, out = run(["upower", "-e"])
    if rc != 0 or not out.strip():
        return devices, False
    paths = [line.strip() for line in out.splitlines()
             if line.strip() and not line.strip().endswith("/DisplayDevice")]
    for device_path in paths:
        match = UPOWER_DEVICE_RE.match(device_path)
        if not match:
            continue
        native_id = match.group(1)
        if native_id in existing_ids:
            continue
        rc, info = run(["upower", "-i", device_path])
        if rc != 0:
            continue
        percent = None
        state = None
        model = None
        serial = None
        power_supply = None
        for line in info.splitlines():
            stripped = line.strip()
            if stripped.startswith("native-path:"):
                native = stripped.split(":", 1)[1].strip()
                # Align with the sysfs scan when UPower reports a kernel
                # power-supply device; BlueZ-backed devices keep the UPower
                # object name.
                if native.startswith("/sys/class/power_supply/"):
                    native_id = native.rsplit("/", 1)[-1] or native_id
            elif stripped.startswith("power supply:"):
                power_supply = stripped.split(":", 1)[1].strip() == "yes"
            elif stripped.startswith("percentage:"):
                raw = stripped.split(":", 1)[1].strip()
                percent = _int(raw.split("%")[0].strip())
            elif stripped.startswith("state:"):
                state = stripped.split(":", 1)[1].strip()
            elif stripped.startswith("model:"):
                model = stripped.split(":", 1)[1].strip() or None
            elif stripped.startswith("serial:"):
                serial = stripped.split(":", 1)[1].strip() or None
        # UPower's keyboard backend mirrors BlueZ Battery1 devices; drop the
        # duplicate so each peripheral appears once.
        if serial and serial.lower() in bt_addresses:
            continue
        if model and model.lower() in bt_names:
            continue
        if native_id in existing_ids:
            continue
        if power_supply is False and model is None and percent is None:
            continue
        devices.append({
            "source": "upower",
            "id": native_id,
            "name": model or native_id,
            "icon": None,
            "kind": kind_from_name(model),
            "address": None,
            "model": model,
            "connected": True,
            "percent": percent,
            "charging": state == "charging",
            "state": state.title() if state else None,
            "batteryLevels": None,
        })
        existing_ids.add(native_id)
    return devices, True


# --------------------------------------------------------------------------
# Razer (python-openrazer)
# --------------------------------------------------------------------------

RAZER_KIND_MAP = {
    "keyboard": "keyboard",
    "keypad": "keyboard",
    "mouse": "mouse",
    "mousemat": "other",
    "headset": "headset",
    "speaker": "speaker",
    "other": "other",
}


def collect_razer():
    try:
        from openrazer.client import DeviceManager  # noqa: PLC0415
    except Exception:
        return [], False
    try:
        manager = DeviceManager()
        razer_devices = list(manager.devices)
    except Exception:
        return [], False
    if not razer_devices:
        return [], True
    devices = []
    for device in razer_devices:
        try:
            name = getattr(device, "name", None) or "Razer device"
            kind = RAZER_KIND_MAP.get(getattr(device, "type", ""), "other")
            percent = getattr(device, "battery_level", None)
            if percent is not None:
                percent = _int(percent)
            charging = getattr(device, "is_charging", None)
            serial = getattr(device, "serial", None) or str(id(device))
            devices.append({
                "source": "razer",
                "id": "razer-" + str(serial),
                "name": name,
                "icon": None,
                "kind": kind,
                "address": None,
                "model": None,
                "connected": True,
                "percent": percent,
                "charging": bool(charging) if charging is not None else None,
                "state": "Charging" if charging else ("Discharging" if percent is not None else None),
                "batteryLevels": None,
            })
        except Exception:
            continue
    return devices, True


# --------------------------------------------------------------------------
# assembly
# --------------------------------------------------------------------------

def main():
    devices = []
    sources = {
        "bluetooth": False,
        "sysfs": False,
        "upower": False,
        "razer": False,
    }

    bt_devices, sources["bluetooth"] = collect_bluetooth(bluez_objects())
    devices.extend(bt_devices)

    sysfs_devices, sources["sysfs"] = collect_sysfs()
    devices.extend(sysfs_devices)
    sysfs_ids = {device["id"] for device in sysfs_devices}

    upower_devices, sources["upower"] = collect_upower(
        set(sysfs_ids), bluetooth_devices=bt_devices)
    devices.extend(upower_devices)

    razer_devices, sources["razer"] = collect_razer()
    devices.extend(razer_devices)

    document = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "ok": True,
        "sources": sources,
        "devices": devices,
    }
    json.dump(document, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
