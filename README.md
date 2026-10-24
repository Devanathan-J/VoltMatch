# ⚡ VoltMatch

> **"Know Before You Connect."**  
> An intelligent USB-C Power Delivery (USB-PD) compatibility checker, live hardware power meter, and screen-off remote charging telemetry monitor built with Flutter & Android native APIs.

---

## 📱 Overview

Most consumers struggle to answer everyday charging questions:
- *Can my 65W laptop charger safely power my 18W phone?*
- *Why is my 44W fast-charging phone only drawing ~7W when I open a battery app?*
- *Is this mystery USB-C cable rated for high current, and does it support data transfer?*

**VoltMatch** solves these problems with a two-fold approach:
1. **Deterministic Rules Engine**: Mathematically evaluates manufacturer fixed USB-PD profiles, cable current ratings, and device tolerances without guessing or hallucinating safety claims.
2. **Real-Time Hardware Telemetry & Remote Probe**: Measures battery current, voltage, and charging wattage on-device, with a built-in local Wi-Fi broadcaster that lets you monitor true fast-charging speeds while your phone screen stays completely **OFF**.

---

## ✨ Key Features

### 1. 🧩 Deterministic Compatibility Engine
- Evaluates fixed USB-PD profiles ($V \times A = W$).
- Respects device minimum and recommended wattage requirements.
- Automatically handles cable constraints (e.g., standard 3A vs 5A e-marked cables).
- Returns 4 distinct, color-coded verdict states:
  - 🟢 **Compatible Under Stated Conditions**
  - 🟡 **Limited / Slower Charging**
  - 🔴 **Incompatible Within Supported Mode**
  - ⚪ **Cannot Verify (Missing or Unverified Specifications)**

### 2. ⚡ Live Hardware Power Meter
- Real-time battery current ($\text{mA}$) and voltage ($\text{V}$) monitoring via Android's internal `BatteryManager`.
- Instantaneous wattage calculation updated every second.
- Intelligent clamp prevents discharge current from displaying as charging wattage when unplugged.

### 3. 🔌 Cable Data-Wire Inspection
- Inspects connected cables for active **Data Lines (D+ / D-)** vs cheap **Charge-Only** wires using Android's `UsbManager` host handshake.

### 4. 📡 Screen-Off Remote Monitor (Probe Mode)
- **The Problem:** Modern fast-charging protocols (e.g., Vivo/iQOO FlashCharge, Samsung Super Fast Charging) aggressively throttle charging power down to ~7W–10W the moment the screen turns ON to prevent display overheating.
- **The Solution:** VoltMatch acquires an Android `PARTIAL_WAKE_LOCK` and launches an embedded lightweight HTTP/JSON server on port `8080`.
- **How it works:** Turn the broadcaster on, lock the phone (black screen), and monitor the live wattage in real time from **any browser or second phone** over your local Wi-Fi or Hotspot!

### 5. 💡 In-App Charging Guide & Troubleshooter
- Context-aware notices explaining real-world charging phenomena:
  - **Screen-On Thermal Throttling**
  - **The 80% Saturation Rule:** Why lithium-ion batteries taper down power when nearing full capacity.
  - **Protocol Differences:** Distinguishing proprietary protocols (*FlashCharge*, *SuperVOOC*, *HyperCharge*) from standard USB-PD.

### 6. 💾 Local History Tracker
- Save comparison records locally.
- Review past results and delete individual records with a single tap.

---

## 🛠️ Tech Stack & Architecture

- **Framework:** [Flutter](https://flutter.dev) (Dart SDK `>=3.0.0`)
- **Design System:** Material 3 Dark Palette (`#101419`, `#161D23`, `#1C252C`, `#22BFA2`)
- **Native Android Layer (Kotlin):**
  - `BatteryManager` (`BATTERY_PROPERTY_CURRENT_NOW`, `EXTRA_VOLTAGE`, `EXTRA_STATUS`)
  - `PowerManager` (`PARTIAL_WAKE_LOCK` for screen-off telemetry)
  - `UsbManager` (`android.hardware.usb.action.USB_STATE`)
- **Networking:** Native `dart:io` embedded HTTP server & REST endpoint (`/api/stats`)
- **Local Storage:** `shared_preferences`

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) installed on your system.
- An Android device running Android 8.0 (API 26) or higher.
- A USB-C cable for debugging.

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/voltmatch.git
   cd voltmatch

   