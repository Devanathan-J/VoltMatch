package com.example.voltmatch

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.abs

class ProbeService : Service() {

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    private var targetHubIp: String? = null
    private var isDiscovering = false
    private var isCablePluggedIn = false
    private val deviceName = "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL}"

    // Hardware Event Receiver (Catches the exact moment cable is connected/disconnected)
    private val powerReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_POWER_CONNECTED -> {
                    isCablePluggedIn = true
                }
                Intent.ACTION_POWER_DISCONNECTED -> {
                    isCablePluggedIn = false
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()

        // Register immediate power connection listeners
        val powerFilter = IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
        }
        registerReceiver(powerReceiver, powerFilter)

        startForeground(NOTIFICATION_ID, buildNotification("Ready — Waiting for charger..."))

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VoltMatch::BackgroundProbeWakeLock")
        wakeLock?.acquire(60 * 60 * 1000L)

        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        wifiLock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "VoltMatch::WifiHighPerfLock")
        wifiLock?.acquire()

        VoltMatchTileService.refreshTile(this)
        startAutoDiscoveryAndStreaming()
    }

    // 4-LAYER HARDWARE CHARGER DETECTION (Immune to Vivo/Samsung background broadcast blocks)
    private fun isChargerConnected(): Boolean {
        // 1. Direct hardware connection event
        if (isCablePluggedIn) return true

        // 2. Direct BatteryManager API (Kernel level query)
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && bm.isCharging) {
            return true
        }

        // 3. Direct Hardware Property (API 26+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val statusProp = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)
            if (statusProp == BatteryManager.BATTERY_STATUS_CHARGING ||
                statusProp == BatteryManager.BATTERY_STATUS_FULL) {
                return true
            }
        }

        // 4. Fallback sticky intent
        try {
            val batteryStatus = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val plugged = batteryStatus?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
            val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1

            if (plugged > 0) return true
            if (status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL) return true
        } catch (e: Exception) {}

        return false
    }

    private fun startAutoDiscoveryAndStreaming() {
        serviceScope.launch {
            while (isActive && isRunning) {
                if (!isChargerConnected()) {
                    updateNotification("Paused — Connect charger to start streaming")
                    delay(1000)
                    continue
                }

                if (targetHubIp == null && !isDiscovering) {
                    discoverHub()
                }

                targetHubIp?.let { ip ->
                    val payload = sampleBatteryTelemetry()
                    val success = sendTelemetry(ip, payload)
                    if (success) {
                        updateNotification("Streaming to $ip (Charging)")
                    } else {
                        if (!isDiscovering) {
                            serviceScope.launch { discoverHub() }
                        }
                    }
                }

                delay(400)
            }
        }
    }

    private suspend fun discoverHub() {
        if (isDiscovering) return
        isDiscovering = true

        withContext(Dispatchers.IO) {
            // 1. Quick UDP listener
            try {
                val socket = DatagramSocket(8082).apply { soTimeout = 1200 }
                val buf = ByteArray(1024)
                val packet = DatagramPacket(buf, buf.size)
                socket.receive(packet)
                val msg = String(packet.data, 0, packet.length)
                val json = JSONObject(msg)
                if (json.optString("type") == "VOLTMATCH_HUB") {
                    targetHubIp = json.optString("ip")
                    socket.close()
                    isDiscovering = false
                    return@withContext
                }
                socket.close()
            } catch (e: Exception) {}

            // 2. Parallel Subnet scan fallback
            val localIp = getLocalIpAddress()
            if (localIp != null && localIp.contains(".")) {
                val subnet = localIp.substringBeforeLast(".")
                coroutineScope {
                    for (i in 1..254) {
                        if (targetHubIp != null) break
                        val testIp = "$subnet.$i"
                        if (testIp == localIp) continue

                        launch {
                            try {
                                val url = URL("http://$testIp:8080/api/discover")
                                val conn = (url.openConnection() as HttpURLConnection).apply {
                                    connectTimeout = 300
                                    readTimeout = 300
                                }
                                if (conn.responseCode == 200) {
                                    val text = conn.inputStream.bufferedReader().readText()
                                    val json = JSONObject(text)
                                    if (json.optBoolean("hub")) {
                                        targetHubIp = testIp
                                    }
                                }
                                conn.disconnect()
                            } catch (e: Exception) {}
                        }
                    }
                }
            }
            isDiscovering = false
        }
    }

    private fun sampleBatteryTelemetry(): JSONObject {
        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val batteryStatus = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))

        val rawCurrent = abs(batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW))
        val currentInMA = if (rawCurrent > 10000) rawCurrent / 1000.0 else rawCurrent.toDouble()

        val voltageMv = batteryStatus?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: 0
        val voltageInV = voltageMv / 1000.0

        val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                         status == BatteryManager.BATTERY_STATUS_FULL ||
                         isCablePluggedIn

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

        val liveWatts = if (isCharging) voltageInV * (currentInMA / 1000.0) else 0.0

        return JSONObject().apply {
            put("id", "probe_tile_${Build.MODEL.replace(" ", "_")}")
            put("name", deviceName)
            put("watts", liveWatts)
            put("currentMA", currentInMA)
            put("voltageV", voltageInV)
            put("batteryPct", batteryPct)
            put("tempC", tempC)
            put("maxChargingWatts", maxWatts)
            put("isCharging", isCharging)
        }
    }

    private fun sendTelemetry(hubIp: String, json: JSONObject): Boolean {
        return try {
            val url = URL("http://$hubIp:8080/api/push")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = 1000
                readTimeout = 1000
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("Connection", "Keep-Alive")
            }

            val bytes = json.toString().toByteArray(Charsets.UTF_8)
            conn.outputStream.use { os ->
                os.write(bytes)
                os.flush()
            }

            val code = conn.responseCode
            if (code == 200) {
                conn.inputStream.close()
                true
            } else {
                conn.errorStream?.close()
                false
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun getLocalIpAddress(): String? {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val ipInt = wifiManager.connectionInfo.ipAddress
        if (ipInt == 0) return null
        return String.format(
            "%d.%d.%d.%d",
            ipInt and 0xff,
            ipInt shr 8 and 0xff,
            ipInt shr 16 and 0xff,
            ipInt shr 24 and 0xff
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "VoltMatch Background Probe",
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Streams power telemetry to Central Hub" }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(statusText: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("⚡ VoltMatch Probe Active")
            .setContentText(statusText)
            .setSmallIcon(R.drawable.ic_qs_voltmatch)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(statusText: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(statusText))
    }

    override fun onDestroy() {
        isRunning = false
        serviceScope.cancel()
        try {
            unregisterReceiver(powerReceiver)
        } catch (e: Exception) {}

        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        if (wifiLock?.isHeld == true) {
            wifiLock?.release()
        }
        VoltMatchTileService.refreshTile(this)
        super.onDestroy()
    }

    companion object {
        const val CHANNEL_ID = "voltmatch_probe_channel"
        const val NOTIFICATION_ID = 2044
        var isRunning = false
    }
}