package com.example.voltmatch

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
                "getLivePowerStats" -> {
                    val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                    val batteryStatus = registerReceiver(null, ifilter)

                    // 1. SMART CURRENT AUTO-DETECT (Fixes Samsung vs iQOO/Pixel scale mismatch)
                    val rawCurrent = abs(batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW))
                    val currentInMA = if (rawCurrent > 10000) {
                        // Microamperes (iQOO, Pixel, Xiaomi): divide by 1000
                        rawCurrent / 1000.0
                    } else {
                        // Milliamperes (Samsung Galaxy A-series quirk): already in mA!
                        rawCurrent.toDouble()
                    }

                    // 2. Voltage in Volts
                    val voltageMv = batteryStatus?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: 0
                    val voltageInV = voltageMv / 1000.0

                    // 3. Charging status
                    val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                    val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                                     status == BatteryManager.BATTERY_STATUS_FULL

                    // 4. Battery Level %
                    val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                    val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                    val batteryPct = if (level >= 0 && scale > 0) (level * 100 / scale) else 0

                    // 5. Battery Temp in °C
                    val rawTemp = batteryStatus?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
                    val tempC = rawTemp / 10.0

                    // 6. Hardware Ceiling
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

                    // 7. USB Data Lines check
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
                "acquireWakeLock" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VoltMatch::MonitorWakelock")
                    wakeLock?.acquire(45 * 60 * 1000L)
                    result.success(true)
                }
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