# DX Light (Robobloq QuikLight) LED controller protocol

Recovered statically from `C:\Program Files\DX Light\resources\app.asar`
(app "quiklight-desktop" v3.11.0, Robobloq), the Electron app's bundled main process
(`.webpack/main/index.js`). The core of it was then confirmed on real hardware (see
"Verified on the device" at the end).

## Transport

| Item | Value |
|---|---|
| USB device | `1A86:FE0C` (WCH chip, USB CDC serial), appears as a COM port (COM5 on the dev PC) |
| App constant | `CDC_VID = 6790 (0x1A86)`, `CDC_PID = 65036 (0xFE0C)` |
| Serial settings | 115200 baud, 8 data bits (defaults: no parity, 1 stop bit) |
| Other variants in the app | HID `1A86:FE07` (manufacturer "ROBOBLOQ", see "HID variant (1A86:FE07)" below), BLE, wireless dongle `5656:FFAA` |

Replies come back on the same port, start with ASCII `RB`, and echo the request's
sequence byte at offset 3. The app waits 200 ms for a reply after `write`, 2 ms after
`writeWithoutResponse` (used for color frames).

## "RB" command frame

```
offset 0-1  'R' 'B'            (0x52 0x42)
offset 2    total frame length (bytes, including checksum)
offset 3    sequence id        (2..254, increments, wraps to 1)
offset 4    action
offset 5..  payload
last byte   checksum = (sum of all previous bytes) & 0xFF
```

### Actions

| Action | Code | Payload |
|---|---|---|
| setSyncScreen | 0x80 | (uses the "SC" frame below) |
| writeDeviceInfo | 0x81 | u16BE, u8, u8, 0x01, u16BE (LED count config) |
| readDeviceInfo | 0x82 | none, see reply layout below |
| readDeviceUUID | 0x83 | none, reply bytes 5..12 = UUID |
| setLedEffect | 0x85 | effectIndex, param (built-in animations) |
| **setSectionLED** | **0x86** | N x 5-byte groups (see below) |
| setBrightness | 0x87 | brightness |
| setAutoOff | 0x89 | a, b |
| setDynamicSpeed | 0x8A | speed |
| setSoundSensitivity | 0x8B | sensitivity |
| setExternalAudio | 0x91 | u16BE |
| setOpenUrl | 0x93 | u8 |
| setLampsAmount | 0x95 | LED count |
| setWhiteBright | 0x96 | a, b |
| turnOffLight | 0x97 | none |
| setComputerRhythm | 0x98 | a, b (music mode) |
| (reply) sync-screen status report | 0xF1 | byte 6 = on/off |

### readDeviceInfo reply (0x82)

| Bytes | Meaning |
|---|---|
| 5..7 | device id (hex string, used for per-model tweaks) |
| 8 | display size |
| 11 | **LED count (lampsAmount)** |
| 12..19 | UUID |
| 21..23 | firmware version (major.minor.patch) |

## Color data: 5-byte range groups

Both `setSectionLED` and the screen-sync frame carry groups of:

```
[startLed, R, G, B, endLed]     LEDs are 1-based, range inclusive
```

- `endLed = 254` means "to the end of the strip". Solid color = `[1, R, G, B, 254]`.
- One group per LED (`[i, R, G, B, i]`) gives full per-LED control.
- Byte order follows the user's `wireMap` setting (default "RGB"); some strips need GRB etc.

### Real-time streaming (how screen sync works)

- **Firmware > 1.0.2**: one "SC" frame per update:
  ```
  'S' 'C' (0x53 0x43), u16BE total length, sequence id, 0x80, groups..., checksum
  ```
- **Older firmware**: the groups are split into chunks of 55 bytes (11 groups), each sent as an
  `RB 0x86 setSectionLED` frame, with 20 ms between chunks.

Before sending, the app only applies cosmetic tweaks (optional saturation boost, dimming of
near-black colors), so they are not needed for a driver.

## Built-in effects and music

- `setLedEffect (0x85)` takes `[effectType, effectIndex]`. `effectType 3` is music ("rhythm").
- DX Light's music has two sources (`rhythmType`): `2` = the controller's own microphone,
  `1` = computer audio. DX Light only uses computer audio for the **HID** variant (`1A86:FE07`)
  on firmware >= 1.8.2. On this USB-serial controller its music mode is mic-only.
- `setComputerRhythm (0x98)` = `[effectIndex, level 0..100]`. This is how PC audio levels would be
  fed to the controller's own music effects. Untested on this device (see the app's
  "PC audio -> controller effects" option).

## HID variant (1A86:FE07)

Newer controllers ship as a USB HID device instead of a USB CDC serial port. They accept the
**exact same `RB` and `SC` frame layouts** and the **same 8-bit additive checksum**
(`sum(bytes before checksum) & 0xFF`) as the `1A86:FE0C` serial model—only the USB transport
framing differs, so one driver or SignalRGB plugin can support both models with the same frame
builders.

### USB descriptors and interfaces

Verified on macOS (`ioreg` on a `1A86:FE07` controller):

| Item | Value |
|---|---|
| USB VID:PID | `1A86:FE07` (`0x1a86:0xfe07`, vendor `6790`, product `65031`) |
| Strings / revision | Manufacturer `"ROBOBLOQ"`, product `"USBHID"`, serial `"0123456789"`, `bcdDevice 0x0100` |
| Interface 1 (lighting) | Vendor-defined collection: `usagePage 0xFF00`, `usage 1` (`0x01`), 64-byte input & output reports, **no report ID** |
| Interface 2 (keyboard) | Boot keyboard collection: `usagePage 0x01`, `usage 0x06` (ignored for lighting; blocked by WebHID) |

Vendor lighting HID report descriptor (34 bytes):

```
06 00 ff 09 01 a1 01 09 02 26 ff 00 75 08 15 00 95 40 81 06 09 02 15 00 26 ff 00 75 08 95 40 91 06 c0
(0600ff0901a101090226ff0075081500954081060902150026ff00750895409106c0)
```

Because the controller exposes both interfaces under `1A86:FE07`, WebHID must filter by the
vendor usage page and usage so the browser picker only lists the lighting interface:

```js
{ vendorId: 0x1a86, productId: 0xfe07, usagePage: 0xff00, usage: 1 }
```

### 64-byte report framing and multi-report splitting

- **Output reports:** 64-byte payload sent with `reportId = 0` (`device.sendReport(0, report)` in
  WebHID; on native HID APIs such as Windows HID or Linux `/dev/hidraw`, a 65-byte write with byte
  `0 = 0x00` and bytes `1..64` carrying the 64-byte chunk).
- **Single-report frames (`<= 64` bytes):** the `RB` or `SC` frame is copied to offset `0` of a
  64-byte buffer and zero-padded to 64 bytes.
- **Multi-report frames (`> 64` bytes):** longer frames (such as per-LED `SC` frames) are split
  into consecutive 64-byte continuation reports at byte offsets `0, 64, 128, ...`. Continuation
  reports carry the next raw bytes of the same frame with **no extra header**, the final report is
  zero-padded to 64 bytes, and reports are awaited in order with a `1 ms` pause between
  continuation reports of the same frame.

### Input reports and `readDeviceInfo` (`0x82`) reply

- **Input reports:** arrive as 64-byte payloads (`reportId = 0`) with the `RB` reply at offset `0`
  and trailing zero padding. When bytes `0..1` are `'R' 'B'` (`0x52 0x42`), byte `2` gives the
  exact frame length (`6..64`) so the trailing zeros can be trimmed before logging or parsing.
- **`readDeviceInfo` (`0x82`) reply layout:** identical to the serial model—`0..1` `'R' 'B'`, `2`
  length (`0x18` = 24), `3` echoed sequence ID, `4` action `0x82`, `5..7` device ID, `8` display
  size (inches), `11` LED count (`lampsAmount`), `12..19` UUID, `21..23` firmware version
  (`major.minor.patch`). Older replies may be queued ahead of the current query, so readers should
  scan incoming reports for an `RB` frame with action `0x82` at byte `4` matching the request's
  sequence ID at byte `3`.

### Reference

HID report framing, multi-report splitting, the 1 ms inter-report pause, and the `0xFF00`/`1`
interface filter were confirmed against **HyperHDR's SyncLight HID driver**
(`DriverHidSyncLight.cpp` and `SyncLightProtocol.md` in
[`awawa-dev/HyperHDR`](https://github.com/awawa-dev/HyperHDR) under `sources/led-drivers/hid/`).

## Verified on the device

Tested against the real controller (firmware 1.1.2, device id `000603`, display size 27, 63 LEDs):

- `readDeviceInfo` request `52 42 06 02 82 1e` gets a valid reply; the field layout above is correct.
- Solid color via `RB 0x86 [1,R,G,B,254]` works.
- Per-LED frames work over both transports: `SC` frames and chunked `RB 0x86`.
- Range compression (merging neighbouring LEDs with the same color into one group) is accepted.
- The 3 buttons on the controller (power, mode, music) send **nothing** over USB. They only act
  inside the controller, so the PC can't react to them.
- The controller has no Wi-Fi or Bluetooth. Without a PC it only runs its built-in effects
  (last mode is kept by the controller itself).

## Open questions

- Update rate: frames sent every ~50 ms made an animated rainbow "freeze" on a fixed pattern,
  while 1 frame/s always updated. The real ceiling is still unknown. The app has an FPS slider
  and skips identical frames; find the highest FPS where effects still move.
- Full list of `setLedEffect` indexes per effect type.
- Whether `setComputerRhythm (0x98)` does anything on this (serial, fw 1.1.2) controller.
