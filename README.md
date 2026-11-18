# OpenDX

An open replacement for **DX Light**, the desktop app for Robobloq / "QuikLight" USB LED strip
controllers (the kind sold as monitor or desk backlights). It works on **Windows and macOS** in
Edge or Chrome, talks directly to both the **USB-serial (`1A86:FE0C`)** and **USB-HID
(`1A86:FE07`)** controller models over Web Serial / WebHID, and does everything DX Light does:
static colors, effects, music and screen sync. It adds more effects, PC-audio music and a proper
LED layout editor.

## Why this exists

DX Light works, but it's a heavy Electron app with cloud and telemetry bits, a clunky UI, and its
music mode only listens to the controller's own microphone. The goal was to get rid of it:

1. Find out how DX Light talks to the controller.
2. Build a cleaner app that controls the strip the same way. **This repo.**
3. Next: write a **SignalRGB plugin** so the strip syncs with the rest of the RGB setup.

## Quick start

### Windows

1. Install [Node.js](https://nodejs.org) (only used for a tiny local web server).
2. Double-click **`app/Start OpenDX.bat`**. It closes DX Light (which locks the COM
   port), starts the server on `http://localhost:8642` and opens the app in an Edge window.
3. Click **Connect** and pick the controller. It reconnects automatically after that.
4. Use ⏻ to turn the strip on or off, then pick a mode.

To stop it, close the app window and the minimized "OpenDX server" window.
To keep DX Light from coming back, disable it in Task Manager > Startup apps.

### macOS

1. Install [Node.js](https://nodejs.org) (only used for a tiny local web server) and **Google Chrome** or **Microsoft Edge**.
2. Double-click **`app/Start OpenDX.command`**. It starts the local server on `http://localhost:8642` (if not already running) and opens the app in a Chrome or Edge app window without closing any other apps.
3. Click **Connect**, choose **HID (FE07)** or **USB serial (FE0C)**, and pick the controller. It reconnects automatically after that.
4. Use ⏻ to turn the strip on or off, then pick a mode.

## What i found (summary)

Full details, with byte layouts, are in [DX-Light-protocol.md](DX-Light-protocol.md).

- **How it was found:** DX Light is an Electron app. Its `resources/app.asar` was unpacked
  (`npx @electron/asar extract`), and `.webpack/main/index.js` was beautified and read. The
  protocol lives there in plain JavaScript. The extracted code isn't part of this repo
  (`.gitignore` blocks it).
- **Device:** Two USB controller variants share the same protocol:
  - **USB-serial (`1A86:FE0C`):** WCH USB CDC serial port, 115200 baud 8N1. No custom driver or encryption.
  - **USB-HID (`1A86:FE07`):** manufacturer `"ROBOBLOQ"`, product `"USBHID"`. Uses the same `RB` and `SC` frames and 8-bit sum checksum, sent as 64-byte HID output reports (`reportId = 0`, split across continuation reports when > 64 bytes) on vendor usage page `0xFF00` / usage `1`.
- **Frames:** `RB` command frames (`'R' 'B' len seq action payload checksum`), plus an `SC` frame
  for fast per-LED updates on firmware > 1.0.2. The checksum is the sum of all bytes & 0xFF.
- **Colors:** 5-byte groups `[startLed, R, G, B, endLed]`, 1-based and inclusive, where `254`
  means "to the end". A run of same-colored LEDs can be one group.
- **Test device:** firmware 1.1.2, 63 LEDs, reported by the controller itself (`readDeviceInfo`).
- **Hardware limits:** USB only, no Wi-Fi or Bluetooth. Its 3 buttons don't send anything to the
  PC. The controller's built-in music uses its onboard mic. On a wall charger it just runs its
  built-in effects.
- **Open questions:** the maximum frame rate (fast streaming once froze an animation), the full
  list of built-in effect indexes, and whether the "PC audio levels → controller" command (`0x98`)
  works on this model.

## How the app works

Everything is in one file, [app/index.html](app/index.html), with no build step
and no dependencies. [serve.js](app/serve.js) only serves it on `127.0.0.1`, because
Web Serial and WebHID need a secure origin.

| Part | Where (search for) | Notes |
|---|---|---|
| Settings | `DEFAULTS`, `save()` | Saved in the browser's `localStorage` (key `ledctl`), not on the controller |
| Protocol | `rbFrame`, `scFrame`, `toGroups`, `ACT` | Byte-for-byte checked against frames the device accepted |
| Device I/O | `connect`, `FILTER`, `HID_FILTER` | Web Serial (`1A86:FE0C`) + WebHID (`1A86:FE07`, `0xFF00`/`1`); reads device info on connect, sets the LED count, picks SC or RB transport by firmware |
| Effects | `EFFECTS` | 17 effects, rendered in JS and streamed to the strip |
| Music | `startMusicSource`, `MUSIC` | Sources: PC audio (screen share + system audio), mic, controller mic, PC audio → controller (experimental) |
| Screen sync | `startScreen`, `layoutLeds`, `renderScreen`, `autoLayout` | Captures at 128×72 and averages an edge region per LED. Layout = LEDs per side + start corner + direction |
| Output | `tick`, `finalize` | A Worker timer drives the loop, so it keeps running when minimized. Applies brightness, color order and reverse, then skips unchanged frames (1 s keep-alive) |
| Hardware tab | `setMode("hardware")`, `ACT.setLedEffect` | Raw access to the controller's built-in effects |

## Status

- **Done:** protocol decoded and verified, app with all DX Light modes plus extras, Windows and macOS launchers, Web Serial (`1A86:FE0C`) and WebHID (`1A86:FE07`) support.
- **Needs testing on the strip:** effect smoothness and max FPS, color order, screen-sync layout,
  Hardware tab effects, and the experimental PC audio → controller music.
- **Next:** the SignalRGB plugin. Both `1A86:FE0C` (serial) and `1A86:FE07` (HID) take the same `RB`/`SC` frames and `sum & 0xFF` checksum: on connect, read
  `readDeviceInfo` for the LED count, then send one `SC` frame per frame using `toGroups` range
  compression. Use the same frame rate that works in the app.
- **Idea:** for Wi-Fi, standalone use and native SignalRGB/WLED support, the strip itself
  (probably WS2812B) could be wired to a WLED board instead of this controller.

## Repo layout

```
DX-Light-protocol.md        full protocol reference
app/
  index.html                the whole app
  serve.js                  local static server (127.0.0.1:8642)
  Start OpenDX.bat          Windows launcher
  Start OpenDX.command      macOS launcher
```

Not affiliated with Robobloq. The protocol was worked out for interoperability with hardware I own.
