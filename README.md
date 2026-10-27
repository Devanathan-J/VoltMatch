<p align="center">
  <img src="assets/icons/app_icon.png" width="140" height="140" alt="VoltMatch Logo" style="border-radius: 50%;" />
</p>

<h1 align="center">⚡ VoltMatch</h1>

<p align="center">
  <strong>Know Before You Connect.</strong><br>
  The ultimate cross-platform utility to check charger compatibility, monitor live watts, and track multi-device charging from your desktop.
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

If you manage **multiple devices** (smartphones, tablets, work phones) while working at your laptop or desktop, **VoltMatch is built for you**. 

We’ve all been there: you plug in your phone in another room, get deep into work, and completely forget about it—leading to overcharged batteries and excess heat. VoltMatch lets you monitor all your charging devices live on your computer monitor and sounds a gentle chime when any device reaches **80%**, so you never forget to unplug!

---

## 📱 What Can VoltMatch Do? (Short & Sweet)

- **🧩 Smart Compatibility Checker**: Select or 1-tap auto-detect your phone model to instantly verify if your USB-C charger and cable will deliver safe, fast power.
- **⚡ Live Hardware Power Meter**: Measure real-time Watts, milliamps, voltage, and battery thermals directly from your phone or laptop hardware.
- **📡 Multi-Device Telemetry Hub**: Stream charging curves from up to 10 phones simultaneously onto a single screen while phone screens stay completely **OFF**.
- **🔔 80% Battery Safeguard**: Sounds an alert chime every 10 seconds and pops up desktop notifications when your batteries reach 80% health capacity.

---

## ✨ Key Features & Debugging Architecture

### 1. 🧩 Smart Multi-Brand Compatibility Checker
- **Brand & Model Filtering**: Filter across **Apple, Samsung, iQOO/Vivo, OnePlus, Xiaomi, Google Pixel, Nothing, Motorola, and Laptops**.
- **✨ 1-Tap Hardware Auto-Detection**: Cross-references internal Android hardware model codes (e.g., `I2206` $\rightarrow$ *iQOO Z6 44W*, `SM-A217F` $\rightarrow$ *Samsung Galaxy A21s*) mapped from the open-source `KHwang9883/MobileModels` database.
- **Deterministic Math**: Evaluates voltages, current limits, and cable bottlenecks ($V \times I = W$) to deliver 4 clear safety verdicts.

### 2. ⚡ Live Hardware Power Meter & Cable Tester
- **Real-Time Electricity Gauging**: Live Watts, milliamps ($\text{mA}$), and Volts updated every 300ms–400ms.
- **Smart Sensor Auto-Detection**: Solves Android vendor scaling quirks (Samsung Galaxy mA vs. Qualcomm/iQOO $\mu\text{A}$), preventing false `0.0 W` readings.
- **Laptop Power Detection (Windows)**: Reads real-time battery charge rates in Watts via WMI/ACPI on Windows laptops, and detects direct AC wall power on desktop towers.
- **Cable Data-Line Inspector**: Tests connected cables for active **Data Lines (D+/D-)** vs **Charge-Only** wires.

### 3. 🖥️ Native Windows Mission Control (`.exe`) & Android Quick Access
- **In-App Desktop Dashboard**: Transforms the Windows `.exe` window into a widescreen Mission Control grid with 60 FPS sparkline charts.
- **Windows 10/11 Toast Notifications & Chime**: Pops up native notification banners and plays synchronous audio alerts when devices reach 80%+.
- **Administrator / Firewall Access (required to discover devices)**: `voltmatch.exe` runs with Administrator privileges (UAC prompt) so it can add the inbound Windows Firewall rules needed to discover and receive telemetry from phones. Without admin access, phones may not show up.
- **📥 CSV Session Exporter**: Export full multi-device charging sessions with timestamps, Watts, and thermals to your `Downloads` folder with one click.
- **⚡ Android Quick Settings Tile**: Add VoltMatch to your phone's swipe-down notification shade for 1-tap background streaming without opening the app.

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

> **Windows Firewall / Admin access (required to see other devices):** `voltmatch.exe` requests Administrator privileges on launch (UAC prompt) so it can add the inbound Windows Firewall rules it needs. **If you do not run it as Administrator (or decline the UAC prompt), inbound connections on the Wi-Fi (Public) profile are usually blocked and your phones will not be discovered — devices will not show up.** In that case, run `voltmatch.exe` as Administrator once so it can add the firewall rules, or manually allow **VoltMatch** through Windows Firewall for TCP port `8080` and UDP port `8082`. Also make sure the PC and phone are on the same subnet.

---

## � Direct Downloads

| Platform | Status | Download Link |
| :--- | :--- | :--- |
| **Android (APK)** | Active | *[Download APK](https://github.com/Devanathan-J/VoltMatch/releases/download/v1.0.0/VoltMatch_v1.0.0_release.apk)* |
| **Windows (.exe)** | Active | *[Download EXE](https://github.com/Devanathan-J/VoltMatch/releases/download/v1.0.0/VoltMatch_Windows_v1.0.0.zip)* |
| **iOS (IPA)** | 🟡 Coming Soon | *Link will be added here* |

---

## �📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.