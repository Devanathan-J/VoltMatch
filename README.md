<p align="center">
  <img src="assets/icons/app_icon.png" width="140" height="140" alt="VoltMatch Logo" style="border-radius: 50%;" />
</p>

<h1 align="center">⚡ VoltMatch</h1>

<p align="center">
  <strong>Know Before You Connect.</strong><br>
  Smart USB-C Compatibility Checker, Live Hardware Power Meter & Multi-Device Screen-Off Telemetry Hub.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android" />
  <img src="https://img.shields.io/badge/License-MIT-teal.svg?style=for-the-badge" alt="License" />
</p>

---

## 📱 What is VoltMatch?

Most users encounter frustrating charging mysteries:
- *Can I use my 65W laptop charger on my 18W phone safely?*
- *Why is my 44W fast-charging phone only pulling ~7W when I open an app?*
- *Why did one phone report `0.0 W` even while fast charging?*
- *Does this mystery cable have data wires, or is it a cheap charge-only wire?*
- *Can I monitor 2 or more phones charging in another room from my laptop screen?*

**VoltMatch** solves all of these with physical electrical rules and real-time hardware telemetry:
1. **Compatibility Engine**: Runs deterministic math on fixed USB-PD profiles without hallucinating safety ratings.
2. **Live Hardware Meter**: Reads battery current ($\text{mA}$), voltage ($\text{V}$), and thermals directly from Android’s internal power supply chips.
3. **Multi-Device Central Hub**: Runs an embedded local web server so you can stream live charging curves for **up to 10 devices simultaneously onto a single URL** while phone screens stay completely **OFF**.

---

## ✨ Key Features

### 1. 🧩 Smart Multi-Brand Compatibility Checker
- **Brand & Model Filtering**: Search or filter by **Apple, Samsung, iQOO / Vivo, OnePlus, Xiaomi, Google Pixel, Nothing, Motorola, and Laptops (MacBook, Dell, Lenovo)**.
- **+ Custom Device & Charger Creator**: Add unlisted or brand-new devices on the fly without waiting for an app update.
- **Deterministic Math**: Evaluates voltages, current limits, and cable bottlenecks ($V \times I = W$) to deliver 4 clear verdicts:
  - 🟢 **Compatible Under Stated Conditions**
  - 🟡 **Limited / Slower Charging**
  - 🔴 **Incompatible Within Supported Mode**
  - ⚪ **Cannot Verify (Missing or Unverified Specs)**

### 2. ⚡ Live Hardware Power Meter & Cable Tester
- **Real-Time Electricity Gauging**: Live Watts, milliamps ($\text{mA}$), and Volts updated every **300ms**.
- **Smart Sensor Auto-Detection**: Fixes the Android vendor quirk where Samsung Galaxy A-series phones report current in $\text{mA}$ while Qualcomm/iQOO devices report in $\mu\text{A}$, preventing false `0.0 W` readings.
- **Hardware Negotiated Ceiling**: Displays the charger's advertised capability (e.g., `⚡ Hardware Limit: 44W`) alongside the battery's actual draw.
- **Cable Data-Line Inspector**: Tests connected cables for active **Data Lines (D+/D-)** vs **Charge-Only** cables.
- **Battery Thermals**: Live temperature tracker in °C with thermal throttling indicators (🟢 Cool, 🟡 Warm, 🔴 Throttling).

### 3. 📡 Multi-Device Central Hub (Up to 10 Phones on 1 IP)
- **The Screen-On Problem**: Modern phones throttle power from 44W/65W down to ~7W–10W when the screen is turned ON to protect the display from heat.
- **The Screen-Off Solution**: VoltMatch acquires an Android `PARTIAL_WAKE_LOCK`. You turn the screen **completely black**, and your phone pumps full fast-charging power while quietly broadcasting live telemetry.
- **Unified Single IP Dashboard**: 
  - **Phone 1 (Central Hub)** hosts the dashboard.
  - **Phones 2 through 10 (Remote Probes)** join and push their telemetry.
  - Open **one single URL** in Chrome on your laptop or tablet to watch all devices in an auto-resizing, responsive grid with live sparkline charts!
- **Zero-Lag 300ms Updates**: Ultra-smooth real-time metrics with instant offline detection (`🛑 Broadcast Stopped`) when a session ends.

### 4. 🔔 80% Smart Battery Alert (Mild Browser Chime)
- Taps into the Web Audio API to play a gentle, crystal-clear bell chime directly through your browser every 10 seconds once any phone reaches **80%+ charge**.
- **Two-Way Sync**: Toggle the sound alert from the mobile app OR from the web browser—both interfaces stay in 100% lockstep.

### 5. 💾 Local Comparison History
- Review past compatibility checks.
- Delete individual comparisons one-by-one or clear all with a single tap.

---

## 📖 How to Use the App (Step-by-Step)

### 🧪 1. Checking Charger Compatibility
1. Open **VoltMatch** and tap **Check Compatibility**.
2. **Select Device**: Choose your brand (e.g. *Samsung*) or search your model (*S24 Ultra*).
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

### 🚀 3. Testing True 44W+ Fast Charging (Screen-Off Mode)
1. Ensure both devices are connected to the **same Wi-Fi** (or connect one phone to the other's Mobile Hotspot).
2. On your primary phone (e.g. **iQOO Z6**), open **Remote Screen-Off Monitor**.
3. Select **Central Hub (Host)** and tap **Start Single-IP Central Hub**.
4. Tap **Copy Single Hub URL** (e.g. `http://192.168.0.175:8080`).
5. Open that URL in Chrome on your laptop, tablet, or secondary phone.
6. Plug in your 44W fast charger and **press the power button to turn the screen OFF**.
7. Watch your laptop screen: without display heat, your charging wattage will ramp up to maximum speed!

---

### 📱 4. Monitoring Multiple Phones on a Single Screen (Up to 10 Devices)
1. **On Phone 1 (e.g. iQOO):** Start as **Central Hub** (e.g., at `192.168.0.175`).
2. **On Phone 2..10 (e.g. Samsung, friend's phone):**
   - Open **Remote Screen-Off Monitor**.
   - Tap the top tab: **Join as Probe**.
   - Type or paste Phone 1's IP address (`192.168.0.175`) and tap **Connect to Central Hub**.
3. **Open the single link (`http://192.168.0.175:8080`) on your computer:**
   - Both (or all 10) phones will appear side-by-side in real time!
   - When any phone reaches 80%, your laptop will sound a mild "ting" chime every 10 seconds to let you know it's time to unplug.

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
- **Android Native Platform Channel (Kotlin):**
  - `BatteryManager` (`BATTERY_PROPERTY_CURRENT_NOW`, `EXTRA_VOLTAGE`, `EXTRA_TEMPERATURE`, `max_charging_current`, `max_charging_voltage`).
  - `PowerManager` (`PARTIAL_WAKE_LOCK` for screen-off execution).
  - `UsbManager` (`android.hardware.usb.action.USB_STATE`).
- **Networking:** Native `dart:io` embedded HTTP multi-client telemetry server on port `8080`.
- **Web Dashboard:** Pure HTML5 Canvas & Web Audio API (zero external JavaScript dependencies).
- **Storage:** Local cache via `shared_preferences`.

---

## 🚀 Getting Started

### 1. Clone the repository
```bash
git clone https://github.com/YOUR_USERNAME/voltmatch.git
cd voltmatch
2. Install dependencies
code
Bash
flutter pub get
3. Generate App Launcher Icons
code
Bash
dart run flutter_launcher_icons
4. Run on Android
Enable Developer Options and USB Debugging on your phone, then run:
code
Bash
flutter run
5. Run on Web
code
Bash
flutter run -d chrome

📄 License
This project is licensed under the MIT License — see the LICENSE file for details.
