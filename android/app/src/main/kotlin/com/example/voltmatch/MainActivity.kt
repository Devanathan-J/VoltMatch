package com.example.voltmatch // (Keep your package name if different)

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbManager
import android.os.BatteryManager
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.voltmatch/hardware"
    private var wakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLivePowerStats" -> {
                    val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                    val batteryStatus = registerReceiver(null, ifilter)

                    // 1. Current in mA
                    val currentNow = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
                    val currentInMA = abs(currentNow) / 1000.0

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

                    // 5. Battery Temperature in °C (EXTRA_TEMPERATURE is in tenths of a °C)
                    val rawTemp = batteryStatus?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
                    val tempC = rawTemp / 10.0

                    // 6. Charger Negotiated Hardware Ceiling (Read via direct string keys)
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
                    wakeLock?.acquire(30 * 60 * 1000L)
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