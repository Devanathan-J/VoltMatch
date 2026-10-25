package com.example.voltmatch

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbManager
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
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
                // 1. UNIVERSAL NOTIFICATION CHECK & REQUEST (Works on Android 10, 11, 12, 13, 14+)
                "areNotificationsEnabled" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        result.success(nm.areNotificationsEnabled())
                    } else {
                        result.success(true)
                    }
                }

                "requestNotificationPermission" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        // Android 13+ system dialog
                        if (!nm.areNotificationsEnabled()) {
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
                        }
                        result.success(true)
                    } else {
                        // Android 10, 11, 12 (Samsung A21s, etc.) - Opens Notification Settings directly!
                        try {
                            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = android.net.Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(false)
                        }
                    }
                }

                // 2. UNIVERSAL BATTERY OPTIMIZATION CONTROLS
                "isBatteryOptimizationIgnored" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
                    } else {
                        result.success(true)
                    }
                }

                "requestIgnoreBatteryOptimization" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = android.net.Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // Fallback to app details
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = android.net.Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(false)
                        }
                    } else {
                        result.success(true)
                    }
                }

                "openAppInfoSettings" -> {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = android.net.Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    result.success(true)
                }

                // 3. HARDWARE AUTO-DETECTION
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

                // 4. LIVE POWER TELEMETRY
                "getLivePowerStats" -> {
                    val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                    val batteryStatus = registerReceiver(null, ifilter)

                    val rawCurrent = abs(batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW))
                    val currentInMA = if (rawCurrent > 10000) rawCurrent / 1000.0 else rawCurrent.toDouble()

                    val voltageMv = batteryStatus?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: 0
                    val voltageInV = voltageMv / 1000.0

                    val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                    val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                                     status == BatteryManager.BATTERY_STATUS_FULL

                    val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                    val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                    val batteryPct = if (level >= 0 && scale > 0) (level * 100 / scale) else 0

                    val rawTemp = batteryStatus?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
                    val tempC = rawTemp / 10.0

                    val maxCurrentUa = batteryStatus?.getIntExtra("max_charging_current", -1) ?: -1
                    val maxVoltageUv = batteryStatus?.getIntExtra("max_charging_voltage", -1) ?: -1
                    var maxWatts = 0.0
                    if (maxCurrentUa > 0 && maxVoltageUv > 0) {
                        maxWatts = (maxVoltageUv / 1000000.0) * (maxCurrentUa / 1000000.0)
                    }

                    val usbFilter = IntentFilter("android.hardware.usb.action.USB_STATE")
                    val usbStatus = registerReceiver(null, usbFilter)
                    val hasDataConnection = usbStatus?.extras?.getBoolean("connected") ?: false

                    result.success(mapOf(
                        "deviceName" to deviceName,
                        "currentMA" to currentInMA,
                        "voltageV" to voltageInV,
                        "isCharging" to isCharging,
                        "batteryPct" to batteryPct,
                        "tempC" to tempC,
                        "maxChargingWatts" to maxWatts,
                        "hasDataConnection" to hasDataConnection
                    ))
                }

                // 5. WAKELOCKS
                "acquireWakeLock" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VoltMatch::MonitorWakelock")
                    wakeLock?.acquire(45 * 60 * 1000L)
                    result.success(true)
                }

                "releaseWakeLock" -> {
                    if (wakeLock?.isHeld == true) wakeLock?.release()
                    result.success(true)
                }

                // 6. QUICK SETTINGS TILE SYNC
                "isProbeServiceRunning" -> result.success(ProbeService.isRunning)

                "stopProbeService" -> {
                    stopService(Intent(this, ProbeService::class.java))
                    VoltMatchTileService.refreshTile(this)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }
}