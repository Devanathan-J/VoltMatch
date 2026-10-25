<p align="center">
  <img src="assets/icons/app_icon.png" width="140" height="140" alt="VoltMatch Logo" style="border-radius: 50%;" />
</p>

<h1 align="center">⚡ VoltMatch</h1>

<p align="center">
  <strong>Know Before You Connect.</strong><br>
  Cross-Platform USB-C Compatibility Checker, Live Hardware Power Meter & Multi-Device Screen-Off Telemetry Hub.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android" />
  <img src="https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Windows" />
  <img src="https://img.shields.io/badge/License-MIT-teal.svg?style=for-the-badge" alt="License" />
</p>

---

## 📱 What is VoltMatch?

Most consumers and tech enthusiasts encounter frustrating charging mysteries:
- *Can I safely use my 65W laptop charger on my 18W phone?*
- *Why is my 44W fast-charging phone only drawing ~7W when I open an app?*
- *Why did my Samsung phone report `0.0 W` even while fast charging?*
- *Does this mystery cable have data wires, or is it a cheap charge-only wire?*
- *Can I monitor phones charging in another room directly from my Windows PC monitor?*

**VoltMatch** solves all of these with deterministic physical rules and cross-platform hardware telemetry:
1. **Compatibility Engine**: Runs exact math on fixed USB-PD profiles without hallucinating safety ratings.
2. **Live Hardware Meter**: Reads battery current ($\text{mA}$), voltage ($\text{V}$), and thermals on Android, plus AC power and battery charge rates on Windows laptops.
3. **Multi-Device Central Hub**: Runs an embedded telemetry server so you can stream live charging curves for **up to 10 devices simultaneously onto a single screen** while phone screens stay completely **OFF**.

---

## ✨ Key Features

### 1. 🧩 Smart Multi-Brand Compatibility Checker
- **Brand & Model Filtering**: Search or filter by **Apple, Samsung, iQOO / Vivo, OnePlus, Xiaomi, Google Pixel, Nothing, Motorola, and Laptops (MacBook, Dell, Lenovo)**.
- **✨ 1-Tap Hardware Auto-Detection**: Cross-references internal Android model codes (e.g., `I2206` $\rightarrow$ *iQOO Z6 44W*, `SM-A217F` $\rightarrow$ *Samsung Galaxy A21s*) mapped from the open-source `KHwang9883/MobileModels` database to automatically select your phone in one tap.
- **+ Custom Device & Charger Creator**: Add unlisted or brand-new devices on the fly without waiting for an app update.
- **Deterministic Math**: Evaluates voltages, current limits, and cable bottlenecks ($V \times I = W$) to deliver 4 clear verdicts:
  - 🟢 **Compatible Under Stated Conditions**
  - 🟡 **Limited / Slower Charging**
  - 🔴 **Incompatible Within Supported Mode**
  - ⚪ **Cannot Verify (Missing or Unverified Specs)**

### 2. ⚡ Live Hardware Power Meter & Cable Tester
- **Real-Time Electricity Gauging**: Live Watts, milliamps ($\text{mA}$), and Volts updated every **300ms–400ms**.
- **Smart Sensor Auto-Detection**: Solves the Android vendor quirk where Samsung Galaxy A-series phones report current in $\text{mA}$ while Qualcomm/iQOO devices report in $\mu\text{A}$, preventing false `0.0 W` readings.
- **Laptop Power Detection (Windows)**: On Windows laptops, reads real-time battery charge rate in Watts via WMI/ACPI; on desktop PCs, detects direct AC wall power.
- **Hardware Negotiated Ceiling**: Displays the charger's advertised capability (e.g., `⚡ Hardware Limit: 44W`) alongside the battery's actual draw.
- **Cable Data-Line Inspector**: Tests connected cables for active **Data Lines (D+/D-)** vs **Charge-Only** cables.
- **Battery Thermals**: Live temperature tracker in °C with thermal throttling indicators (🟢 Cool, 🟡 Warm, 🔴 Throttling).

### 3. 📡 Multi-Device Central Hub & Screen-Off Probe
- **The Screen-On Problem**: Modern phones throttle power from 44W/65W down to ~7W–10W when the screen is turned ON to protect the display from heat.
- **The Screen-Off Solution**: VoltMatch acquires an Android `PARTIAL_WAKE_LOCK`. You turn the screen **completely black**, and your phone pumps full fast-charging power while quietly broadcasting live telemetry.
- **✨ Zero-Config Wi-Fi Auto-Discovery**: Phones on the same Wi-Fi network automatically detect the Host PC/Phone via UDP beacons and concurrent subnet scanning—**no manual IP typing required!**
- **Smart Platform Defaults**:
  - **Android:** Defaults to **Join as Probe** and immediately scans for the Hub.
  - **Windows Desktop:** Defaults to **Central Hub** and opens the Mission Control view.
- **Zero-Flicker Resilience**: Incorporates a 3-strike packet tolerance rule (2.5s network buffer) so temporary Wi-Fi jitter never triggers false disconnects.

### 4. 🖥️ Native Windows Desktop Mission Control (`.exe`)
- **Native In-App Dashboard**: On Windows, clicking "Central Hub" transforms the desktop app window into an in-app **Mission Control Dashboard** with auto-resizing 2-to-3 column layouts for widescreen monitors.
- **Native Windows 10/11 Toast Notifications**: Fires an official Windows notification banner in the bottom-right corner **once** when any connected phone reaches 80%+.
- **Synchronous Windows Chime**: Plays the crisp native Windows chime (`Windows Notify System Generic.wav` / `chimes.wav` / `[Console]::Beep`) directly through your PC speakers **every 10 seconds** until the phone is unplugged.
- **📥 CSV Session Exporter**: Export full multi-device charging sessions with timestamps, Watts, voltage, and thermals directly to your `Downloads` folder with one click.
- **Desktop Identity**: Compiled with custom 3D glowing circular icon (`app_icon.ico`) and proper `VoltMatch` window title.

### 5. 🎨 Polished Native Dark Splash Screen (Android)
- Replaced the default Android white startup window with a native `#101419` dark background and centered circular 3D logo, completely eliminating white screen flash on cold launch.

### 6. 💾 Local Comparison History
- Review past compatibility checks.
- Delete individual comparisons one-by-one or clear all with a single tap.

---

## 📖 How to Use the App (Step-by-Step)

### 🧪 1. Checking Charger Compatibility
1. Open **VoltMatch** and tap **Check Compatibility**.
2. **Select Device**: Tap **Auto-Detect Current Phone** to identify your model in 1 tap, or search your brand and model.
3. **Select Charger**: Choose your charger brand and wattage (e.g. *Anker 65W* or *Samsung 45W*).
4. **Select Cable**: Pick a 3A cable, 5A cable, or Unknown.
5. Tap **Check Compatibility Now**: Read the color-coded verdict, negotiated wattage, and the step-by-step electrical explanation.

---

### ⚡ 2. Measuring Live Power & Checking Cable Data Wires
1. Plug your phone into any charger or computer.
2. Tap **Live Meter & Cable Tester** on the home screen.
3. **Read the numbers**:
   - The large display shows the live net **Watts** flowing into the battery.
   - Look at **Battery Temp**: if it's over 40°C, the phone will deliberately slow down.
4. **Test Data Lines**: Plug the cable into a laptop/PC.
   - If it turns green (**Verified Active**), the wire can transfer files and photos.
   - If it stays yellow, it is a **charge-only wire**.

---

### 🚀 3. Monitoring Multiple Phones on Your PC (Zero-Config Setup)
1. Make sure your PC and phones are on the **same Wi-Fi** (or connected to Mobile Hotspot).
2. **On your Windows PC (`voltmatch.exe`):**
   - Tap **Remote Monitor** $\rightarrow$ Click **Open In-App Mission Control**.
   - Your desktop window becomes the live command center.
3. **On your Phones (Android):**
   - Tap **Remote Monitor** $\rightarrow$ It opens in **Join as Probe** by default.
   - Within 2 seconds, it auto-detects your PC: **`✨ Hub Auto-Detected: Windows Desktop Host`**.
   - Tap **Auto-Connect**, plug in your charger, and **press the power button to turn off the screen**.
4. **Look at your PC monitor:**
   - All phones stream side-by-side with real-time graphs and live wattage numbers!
   - When any phone reaches 80%, your PC will show a **Windows Toast Notification** and play a gentle chime every 10 seconds.
   - Click **Export CSV** at the top right to save the entire charging session log.

---

## 🧠 Why Does Charging Speed Change? (Charging 101)

| Real-World Phenomenon | Why It Happens |
| :--- | :--- |
| **Screen-On Thermal Brake** | The display and GPU generate heat. To prevent battery damage, phones immediately drop power to **~7W–10W** while the screen is awake. Peak speeds only occur with the screen OFF. |
| **The 80% Saturation Rule** | Fast charging only operates at full speed when the battery is empty (0% to 50%). Above 70%–80%, the battery chemistry enters saturation (CV phase), and the phone deliberately trickles power down to ~10W–13W to prevent swelling. |
| **"FlashCharge" vs "Fast Charging"** | Proprietary protocols (Vivo/iQOO FlashCharge 44W, OnePlus SuperVOOC) require the manufacturer's original 4A/5A cable. If a standard cable is used, the charger falls back to basic 15W/18W charging. |

---

## 🛠️ Tech Stack & Architecture

- **Frontend:** [Flutter](https://flutter.dev) (Dart SDK `>=3.0.0`) with Material 3 Dark Palette (`#101419`, `#161D23`, `#1C252C`, `#22BFA2`).
- **Android Native Layer (Kotlin):**
  - `BatteryManager` (`BATTERY_PROPERTY_CURRENT_NOW`, `EXTRA_VOLTAGE`, `EXTRA_TEMPERATURE`, `max_charging_current`, `max_charging_voltage`).
  - `PowerManager` (`PARTIAL_WAKE_LOCK` for screen-off execution).
  - `UsbManager` (`android.hardware.usb.action.USB_STATE`).
- **Windows Desktop Layer (C++ & PowerShell):**
  - WMI / ACPI `Win32_Battery` query bridge for laptop battery charging telemetry.
  - Windows 10/11 WinRT Toast Notification & Audio API bridge.
  - Custom `.ico` app runner integration.
- **Networking:** Native `dart:io` embedded HTTP multi-client telemetry server on port `8080` with UDP broadcast auto-discovery on port `8082`.
- **Web Dashboard:** Pure HTML5 Canvas & Web Audio API (zero external JavaScript dependencies).
- **Storage:** Local cache via `shared_preferences`.

---

## 🚀 Getting Started

### 1. Clone the repository
```bash
git clone https://github.com/YOUR_USERNAME/voltmatch.git
cd voltmatch

📄 License
This project is licensed under the MIT License — see the LICENSE file for details.