# Fit3Bridge

iOS app to connect Samsung Galaxy Fit3 (SM-R390) to Apple Health via Bluetooth LE.

## Features

- Connects to Galaxy Fit3 (model 4C20/SM-R390) via BLE
- Reads: Steps, Distance, Calories, Heart Rate (live), Battery Level
- Syncs Steps and Distance to Apple HealthKit
- Dark mode UI, zero-scroll single screen
- BLE debug logs viewer (collapsible)
- Builds to IPA via GitHub Actions (no local Mac needed)

## Project Structure

```
fit3bridge/
├── project.yml                    # XcodeGen config
├── Fit3Bridge/
│   ├── Info.plist                 # Permissions & capabilities
│   ├── Fit3Bridge.entitlements    # HealthKit + Bluetooth entitlements
│   ├── Fit3BridgeApp.swift        # App entry point
│   ├── ContentView.swift          # SwiftUI single-screen UI
│   ├── Fit3Manager.swift          # BLE manager (CBCentralManagerDelegate)
│   ├── HealthKitManager.swift     # HealthKit sync
│   └── Assets.xcassets/           # App icon placeholder
└── .github/workflows/build-ipa.yml # CI pipeline
```

## Protocol Details (from Fit3-App / Fit3Free)

| Item | UUID / Value |
|------|-------------|
| Samsung Service | `FEE7` |
| Activity Characteristic | `FEC7` (Notify + Write) |
| Heart Rate Service | `180D` (standard) |
| Heart Rate Char | `2A37` (standard) |
| Battery Service | `180F` (standard) |
| Battery Char | `2A19` (standard) |
| Handshake Command | `01 00 00 00 00 <timestamp-u32-le> <crc>` |
| Activity Request | `02 00 00 00 00 <crc>` |
| CRC | XOR of all preceding bytes |

**Activity Data Packet (16+ bytes):**
- Bytes 0-3: Steps (UInt32 LE)
- Bytes 4-7: Distance in cm (UInt32 LE) → divide by 100 for meters
- Bytes 8-11: Calories (UInt32 LE)

## Build & Deploy (No Local Mac)

### 1. Push to GitHub

```bash
cd /c/Users/JP/Documents/fit3bridge
git init
git add .
git commit -m "feat: initial Fit3Bridge iOS app"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/fit3bridge.git
git push -u origin main
```

### 2. Trigger Build

- Go to your GitHub repo → **Actions** tab → **Build IPA** workflow → **Run workflow**
- Or push to `main` branch

### 3. Download IPA

- Wait for workflow to complete (~5-10 min)
- Click **Fit3Bridge-IPA** artifact to download `Fit3Bridge.ipa`

### 4. Install on iPhone (Windows)

Use **Sideloadly** or **AltStore**:
1. Connect iPhone via USB
2. Open Sideloadly → select IPA → click **Start**
3. Enter Apple ID credentials (for signing)
4. On iPhone: Settings → General → VPN & Device Management → Trust developer profile

## Requirements

- iOS 16.0+
- iPhone with Bluetooth LE
- Samsung Galaxy Fit3 (already initialized/paired once)
- Apple Health permissions granted on first run

## BLE Protocol Notes

The Fit3 requires a time-sync handshake (`0x01` command with current Unix timestamp) before it streams activity data. After handshake, send activity request (`0x02`) to trigger a data packet. The band notifies on `FEC7` characteristic.

Heart rate and battery use standard Bluetooth SIG GATT services (0x180D/0x2A37, 0x180F/0x2A19).

## License

MIT