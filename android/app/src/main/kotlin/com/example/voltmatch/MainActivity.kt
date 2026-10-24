package com.example.voltmatch // (Keep your package name if different)

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbManager
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.voltmatch/hardware"
    private var wakeLock: PowerManager.WakeLock? = null
    private val deviceName = "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL}"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // 1. HARDWARE AUTO-DETECTION (Maps to MobileModels Database)
                "getDeviceInfo" -> {
                    val manufacturer = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
                    val model = Build.MODEL
                    val brand = Build.BRAND.replaceFirstChar { it.uppercase() }
                    val device = Build.DEVICE

                    result.success(mapOf(
                        "manufacturer" to manufacturer,
                        "model" to model,
                        "brand" to brand,
                        "device" to device,
                        "fullName" to "$manufacturer $model"
                    ))
                }

                // 2. LIVE POWER & HARDWARE TELEMETRY
                "getLivePowerStats" -> {
                    val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                    val batteryStatus = registerReceiver(null, ifilter)

                    // Smart Current Auto-Detect (Fixes Samsung mA vs iQOO/Pixel uA scale)
                    val rawCurrent = abs(batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW))
                    val currentInMA = if (rawCurrent > 10000) {
                        // Microamperes (iQOO, Pixel, Xiaomi): divide by 1000
                        rawCurrent / 1000.0
                    } else {
                        // Milliamperes (Samsung Galaxy A-series): already in mA!
                        rawCurrent.toDouble()
                    }

                    // Battery Voltage in Volts
                    val voltageMv = batteryStatus?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: 0
                    val voltageInV = voltageMv / 1000.0

                    // Charging Status
                    val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                    val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                                     status == BatteryManager.BATTERY_STATUS_FULL

                    // Battery Level %
                    val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                    val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                    val batteryPct = if (level >= 0 && scale > 0) (level * 100 / scale) else 0

                    // Battery Temperature in °C
                    val rawTemp = batteryStatus?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
                    val tempC = rawTemp / 10.0

                    // Hardware Negotiated Ceiling (Using string literals to avoid Android hidden SDK errors)
                    val maxCurrentUa = batteryStatus?.getIntExtra("max_charging_current", -1) ?: -1
                    val maxVoltageUv = batteryStatus?.getIntExtra("max_charging_voltage", -1) ?: -1
                    var maxWatts = 0.0
                    var maxV = 0.0
                    var maxA = 0.0
                    if (maxCurrentUa > 0 && maxVoltageUv > 0) {
                        maxV = maxVoltageUv / 1000000.0
                        maxA = maxCurrentUa / 1000000.0
                        maxWatts = maxV * maxA
                    }

                    // Cable Data Lines Detection
                    val usbFilter = IntentFilter("android.hardware.usb.action.USB_STATE")
                    val usbStatus = registerReceiver(null, usbFilter)
                    val hasDataConnection = usbStatus?.extras?.getBoolean("connected") ?: false

                    val response = mapOf(
                        "deviceName" to deviceName,
                        "currentMA" to currentInMA,
                        "voltageV" to voltageInV,
                        "isCharging" to isCharging,
                        "batteryPct" to batteryPct,
                        "tempC" to tempC,
                        "maxChargingWatts" to maxWatts,
                        "maxVoltageV" to maxV,
                        "maxCurrentA" to maxA,
                        "hasDataConnection" to hasDataConnection
                    )
                    result.success(response)
                }

                // 3. BACKGROUND WAKELOCK (Allows screen-off measurement without Android sleeping)
                "acquireWakeLock" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VoltMatch::MonitorWakelock")
                    wakeLock?.acquire(45 * 60 * 1000L) // 45 minutes max
                    result.success(true)
                }

                // 4. RELEASE WAKELOCK
                "releaseWakeLock" -> {
                    if (wakeLock?.isHeld == true) {
                        wakeLock?.release()
                    }
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }
}