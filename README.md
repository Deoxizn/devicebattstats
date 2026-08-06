# Device Battery Stats

An [Omarchy](https://omarchy.org/) (Quattro) plugin that shows battery level and
charging state for wireless peripherals directly on the bar, with a details
popup. Works natively on both the stock Omarchy bar and the Shibumi bar.

The point of the plugin is closing a gap Omarchy does not cover: **2.4GHz
receivers** (Logitech hidpp dongles, Keychron 2.4GHz mode, ...) that expose a
battery through the kernel's `power_supply` class but never show up in BlueZ.
**Bluetooth** keyboards and mice that expose a battery via BlueZ `Battery1` are
covered too, as are **Razer** wireless peripherals through python-openrazer.

## Features

- Bar pill showing one glyph per connected device (keyboard, mouse, ...); the
  classic "battery glyph + lowest percent" is available via the `displayMode`
  setting
- Glyph fills and tints while any device is charging or low
- Hover tooltip listing every device
- Click popup with one row per device: type glyph, name, source, charge state
  and a mini battery bar
- Text and icons automatically sized and colored to match the host bar
- Polls only while a widget is mounted (no background churn)
- Graceful degradation: works with whatever subset of tools is installed

## What it looks like

> Screenshots live in `docs/screenshots/` once you drop them in. To capture
> yours: `grim -g "<bar region>" docs/screenshots/bar.png`.

```
 [ ⌨ 🖱 ]             ← pill on the bar: one glyph per connected device
 [ ⌁ 90% ]            ← ...or `displayMode: "full"` (battery glyph + lowest %)
```

Clicking the pill opens the panel:

```
 ┌────────────────────────────────┐
 │  WIRELESS BATTERIES     2 dev  │
 │  ⌨ Keychron Q6 Max   90% ▁▃▅█  │
 │  🖱 Razer Naga V2 Pro 99% ▁▃▅█  │
 └────────────────────────────────┘
```

## Data sources

`scripts/device-battery.sh` emits one JSON document per run, aggregating with
graceful degradation per source:

| Source    | How it is read                                            |
|-----------|-----------------------------------------------------------|
| Bluetooth | `busctl` object-manager dump of BlueZ, `org.bluez.Battery1` |
| sysfs     | `/sys/class/power_supply/*` (Logitech hidpp, 2.4GHz dongles) |
| upower    | `upower -e` / `upower -i`, deduplicated against BlueZ      |
| Razer     | python-openrazer `DeviceManager` (session bus `org.razer`) |

Environment variables:

- `DEVICEBATT_TIMEOUT` — per-subprocess timeout in seconds (default 5).
- `DEVICEBATT_INCLUDE_SYSTEM=1` — include laptop `System`-scope batteries.

## Requirements

- Quickshell (the shell Omarchy ships)
- Material Symbols Rounded font (installed with Omarchy)
- `busctl`, `upower`, `bluetoothctl` (usual on Omarchy)
- optional: `python-openrazer` for Razer devices

## Install

From a git remote (the normal way):

```sh
omarchy plugin add https://github.com/Deoxizn/devicebattstats.git --enable
```

`omarchy plugin add` clones the repo into `~/.config/omarchy/plugins/`, runs
`omarchy-plugin-validate` on it (refusing anything that fails), then installs
and enables the widget in the right section of the bar. You'll be asked to
confirm before anything runs.

> The URL above is the repo this project is published to; if you installed from
> a fork or a mirror, use your own URL.

The plugin is a `service` + `bar-widget`; the service keeps polling only while
a widget is mounted (every 30 seconds by default).

Enable it later, without reinstalling:

```sh
omarchy plugin enable dev.deoxizn.devicebattstats
```

To enable it manually, add the plugin id to a bar layout entry in
`~/.config/omarchy/shell.json` (or use `omarchy shell edit`):

```json
{ "id": "dev.deoxizn.devicebattstats" }
```

## Development

Work against the live shell by symlinking this checkout into the plugins dir:

```sh
ln -s "$PWD" ~/.config/omarchy/plugins/dev.deoxizn.devicebattstats
```

The shell picks up changes on restart. Before you push, sanity-check the
folder with the same validator the installer uses:

```sh
omarchy-plugin-validate .
```

To switch from a dev symlink to the git-managed install (so `omarchy plugin
update` works), remove the symlink once, then add from the remote:

```sh
rm ~/.config/omarchy/plugins/dev.deoxizn.devicebattstats
omarchy plugin add https://github.com/Deoxizn/devicebattstats.git --enable
```

## Widget settings

Inline layout-entry options:

- `displayMode`: what the bar pill shows:
  - `devices` (default) — one glyph per **connected** device (keyboard, mouse,
    headset, ...), hidden when nothing is connected. A glyph is filled with the
    accent color when that device is low or charging.
  - `full` — a battery glyph plus the lowest known charge percent
  - `icon` — battery glyph only
  - `text` — lowest charge percent only
- `compact`: `true` forces `icon` mode (kept for compatibility with the
  `compact` option Omarchy widgets use)

## Theming

The widget never hard-codes colors or sizes. It reads everything from the host
bar through a small token adapter:

- **Shibumi bar** — the bar exposes its own `VisualTokens`
  (`bar.visualTokens`: `labelSize`, `iconSize`, `ink`, `seal`, `paper`, ...),
  so per-widget color fills configured in Shibumi settings apply to this
  widget too.
- **Stock Omarchy bar / any Quattro host** — [`qml/HostTokens.qml`](qml/HostTokens.qml)
  derives the same interface from the bar's standard properties
  (`fontFamily`, `foreground`, `urgent`, `background`, `barSize`, `vertical`)
  and falls back to the active theme's `Style` / `Color` singletons.

Both tokens expose one interface, so the widget never branches on which bar is
running. If you want to re-theme the widget globally, edit `HostTokens.qml`:

| Token         | Default                          | Used for                     |
|---------------|----------------------------------|------------------------------|
| `fontFamily`  | `bar.fontFamily`                 | every text node              |
| `labelSize`   | `Style.font.body`                | pill percent, device names   |
| `captionSize` | `Style.font.caption`             | panel header, sub-labels     |
| `iconSize`    | `Style.space(15)`                | device glyphs (pill + panel) |
| `ink`         | `bar.foreground`                 | regular text / icons         |
| `seal`        | `bar.urgent`                     | charging / low accent        |
| `paper`       | `bar.background`                 | panel chrome                 |

## Layout

```
devicebattstats/
├── manifest.json          plugin manifest (kinds: service, bar-widget)
├── README.md
├── LICENSE                MIT (c) 2026 Deoxizn
├── .gitignore
├── qml/
│   ├── BarWidget.qml      bar-widget entry point (pill + popup host)
│   ├── Service.qml        service entry point (poller process, shared state)
│   ├── DevicePill.qml     bar pill (glyph + percent), click-target registration
│   ├── DevicePanel.qml    Ui.Panel popup with the device list
│   ├── HostTokens.qml     bar-theming adapter (Shibumi + stock interface)
│   ├── IconText.qml       Material Symbols Rounded text (FILL axis)
│   └── DeviceBattery.js   pure data helpers (normalize, glyphs, summary)
└── scripts/
    ├── device-battery.sh  collector wrapper (bash)
    └── device-battery.py  collector (BlueZ, sysfs, upower, Razer)
```

## How it works with the shell

- The widget resolves its service through
  `bar.shell.serviceFor("dev.deoxizn.devicebattstats")`.
- The pill registers itself as a click target with the host bar, so popup
  click-through forwarding, tooltips, and the open-panel indicator work on any
  bar that follows Quattro's bar-widget contract.
- The popup is a `Ui.Panel` + `KeyboardPanel`. On the Shibumi bar the host's
  `WidgetSlot` hosted-panel adapter repaints the card with Shibumi chrome
  automatically.

## License

MIT © 2026 Deoxizn. See [LICENSE](LICENSE).
