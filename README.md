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
  <img src="https://img.shields.io/badge/Android-13%2B-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android 13+" />
  <img src="https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Windows" />
  <img src="https://img.shields.io/badge/License-MIT-teal.svg?style=for-the-badge" alt="License" />
</p>

---

<p align="center">
  <a href="https://github.com/Devanathan-J/VoltMatch/releases/download/v1.0.0/VoltMatch_v1.0.0_release.apk">
    <img src="https://img.shields.io/badge/Download_Android-v1.0.0.apk-22BFA2?style=for-the-badge&logo=android" alt="Download Android" />
  </a>
  <a href="https://github.com/Devanathan-J/VoltMatch/releases/download/v1.0.0/VoltMatch_Windows_v1.0.0.zip">
    <img src="https://img.shields.io/badge/Download_Windows-v1.0.0.exe-0078D6?style=for-the-badge&logo=windows" alt="Download Windows" />
  </a>
  <a href="#-downloads">
    <img src="https://img.shields.io/badge/Download_iOS-Coming_Soon-A7B0B9?style=for-the-badge&logo=apple" alt="Download iOS" />
  </a>
</p>

---

## 🎯 Who is VoltMatch for?

If you manage **multiple devices** (smartphones, tablets, work devices) while working at your laptop or desktop, **VoltMatch is built for you**. 

We’ve all been there: you plug in your phone across the room, get deep into work, and completely forget about it—leading to overcharged batteries and excess heat. VoltMatch lets you monitor all your charging devices live on your computer monitor and sounds a gentle chime when any device reaches **80%**, so you never forget to unplug!

---

## 📱 What Can VoltMatch Do? (Short & Sweet)

- **🧩 Smart Compatibility Checker**: Select or 1-tap auto-detect your phone model to instantly verify if your USB-C charger and cable will deliver safe, fast power.
- **⚡ Live Hardware Power Meter**: Measure real-time Watts, milliamps, voltage, and battery thermals directly from your phone or laptop hardware.
- **📡 Multi-Device Telemetry Hub**: Stream charging curves from up to 10 phones simultaneously onto a single screen while phone screens stay completely **OFF**.
- **📈 Live Power Oscilloscope**: High-performance real-time waveform with ambient glow gradients, dynamic auto-scaling, and a pulsing live beacon tracking your charging current.
- **🔔 80% Battery Safeguard**: Sounds an alert chime every 10 seconds and pops up desktop notifications when batteries reach 80% health capacity—with per-device mute controls.

---

## ✨ Key Features & Technical Highlights

### 1. 🧩 Smart Multi-Brand Compatibility Checker
- **Brand & Model Filtering**: Filter across **Apple, Samsung, iQOO/Vivo, OnePlus, Xiaomi, Google Pixel, Nothing, Motorola, and Laptops**.
- **✨ 1-Tap Hardware Auto-Detection**: Cross-references internal Android hardware model codes (e.g., `I2206` $\rightarrow$ *iQOO Z6 44W*, `SM-A217F` $\rightarrow$ *Samsung Galaxy A21s*) mapped from the open-source `KHwang9883/MobileModels` database.
- **Deterministic Math**: Evaluates voltages, current limits, and cable bottlenecks ($V \times I = W$) to deliver 4 clear safety verdicts (*Compatible, Limited, Incompatible, Cannot Verify*).

### 2. ⚡ Live Hardware Power Meter & Cable Tester
- **Real-Time Electricity Gauging**: Live Watts, milliamps ($\text{mA}$), and Volts updated every 300ms–400ms.
- **Smart Sensor Auto-Detection**: Solves Android vendor scaling quirks (Samsung Galaxy mA vs. Qualcomm/iQOO $\mu\text{A}$), preventing false `0.0 W` readings.
- **Laptop Power Detection (Windows)**: Reads real-time battery charge rates in Watts via WMI/ACPI on Windows laptops, and detects direct AC wall power on desktop towers.
- **Cable Data-Line Inspector**: Tests connected cables for active **Data Lines (D+/D-)** vs **Charge-Only** wires.

### 3. 📈 Real-Time Power Oscilloscope & Live Metrics
- **Dynamic Waveform**: Smooth custom painter renders charging dynamics with ambient gradient shadows below the curve.
- **Live Beacon Dot**: A pulsing indicator actively rides the crest of the curve, visually tracking power delivery in real-time.
- **Adaptive Auto-Centering**: Automatically scales low-wattage trickle charging (e.g., 1.6W) to prevent flatlining against the floor of the graph.
- **⏱️ Live Charge Countdown**: Real-time estimations calculate **Time-to-80%** and **Time-to-100%** based on battery capacity and instantaneous draw.
- **Charger Utilization Meter**: Displays real-time absorption efficiency against the charger's hardware ceiling.

### 4. 🖥️ Native Windows Mission Control (`.exe`) & Android Quick Access
- **In-App Desktop Dashboard**: Transforms the Windows `.exe` window into an auto-resizing Mission Control grid.
- **Windows 10/11 Toast Notifications & Chime**: Pops up native system notification banners and plays synchronous audio alerts when devices reach 80%+.
- **Android Central Hub Chime**: Plays loud notification ringtones via `RingtoneManager` with haptic feedback when hosting on an Android device.
- **🔕 Per-Device Mute Switches**: Toggle audio alerts on individual device cards without silencing other devices on the hub.
- **📥 CSV Session Exporter**: Export full multi-device charging sessions with timestamps, Watts, and thermals to your `Downloads` folder with one click.
- **⚡ Android Quick Settings Tile**: Add VoltMatch to your phone's notification shade for 1-tap background streaming with the screen locked.

---

## 🛠️ Essential Setup (Best run on Android 13+)

*Note: For the best background streaming performance, **Android 13 or higher** is recommended.*

When opening VoltMatch for the first time, complete the quick setup dialog to ensure Android never kills the background telemetry worker:
1. **Notifications**: Tap **Enable** to allow system notifications (required for the Quick Settings tile and 80% chime).
2. **Unrestricted Battery**: Tap **Set** to change battery optimization from "Optimized" to **Unrestricted** (stops Android from putting Wi-Fi to sleep when the screen is locked).
3. **App Settings (Crucial for Samsung & Vivo)**: Tap **Open** to visit your phone's App Info page, and make sure **"Pause app activity if unused"** or **"Put app to sleep"** is turned **OFF**.

---

## 🚀 How to Use Quick Access & Remote Monitoring

1. Make sure your PC and phones are connected to the **same Wi-Fi network**.
2. **On your Windows PC (`voltmatch.exe`):**
   - Open **Remote Monitor** $\rightarrow$ Click **Open In-App Mission Control**.
3. **On your Phone:**
   - Swipe down your quick settings panel and tap the **⚡ VoltMatch** tile.
   - *Note:* Make sure a **Central Hub is actively running on your PC first**, otherwise the probe will wait until it detects an active Hub on the network.
   - Plug in your charger and **press the power button to turn off the screen**.
4. **View your PC monitor:**
   - Your phone will auto-connect via Zero-Config UDP discovery and stream live wattage curves side-by-side!

> **Windows Firewall / Admin access (required to see other devices):** `voltmatch.exe` requests Administrator privileges on launch (UAC prompt) so it can add the inbound Windows Firewall rules it needs. If you decline the UAC prompt, inbound connections on the Wi-Fi profile may be blocked by Windows. In that case, manually allow **VoltMatch** through Windows Firewall for TCP port `8080` and UDP port `8082`.

---

## 📥 Direct Downloads

| Platform | Status | Download Link |
| :--- | :--- | :--- |
| **Android (APK)** | Active | [Download APK v1.0.0](https://github.com/Devanathan-J/VoltMatch/releases/download/v1.0.0/VoltMatch_v1.0.0_release.apk) |
| **Windows (.exe)** | Active | [Download Windows v1.0.0](https://github.com/Devanathan-J/VoltMatch/releases/download/v1.0.0/VoltMatch_Windows_v1.0.0.zip) |
| **iOS (IPA)** | 🟡 Coming Soon | *Link will be added here* |

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.