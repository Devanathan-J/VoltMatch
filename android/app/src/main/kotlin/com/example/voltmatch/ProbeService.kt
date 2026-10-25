package com.example.voltmatch

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
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
    private var targetHubIp: String? = null
    private var consecutiveFailures = 0
    private val deviceName = "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL}"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Scanning for Hub on Wi-Fi..."))

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VoltMatch::BackgroundProbeWakeLock")
        wakeLock?.acquire(60 * 60 * 1000L) // 1 hour max

        VoltMatchTileService.refreshTile(this)
        startAutoDiscoveryAndStreaming()
    }

    private fun startAutoDiscoveryAndStreaming() {
        serviceScope.launch {
            discoverHub()

            while (isActive && isRunning) {
                targetHubIp?.let { ip ->
                    val payload = sampleBatteryTelemetry()
                    sendTelemetry(ip, payload)
                } ?: run {
                    discoverHub()
                }
                delay(400)
            }
        }
    }

    private suspend fun discoverHub() {
        withContext(Dispatchers.IO) {
            // 1. Quick UDP listener
            try {
                val socket = DatagramSocket(8082).apply { soTimeout = 1500 }
                val buf = ByteArray(1024)
                val packet = DatagramPacket(buf, buf.size)
                socket.receive(packet)
                val msg = String(packet.data, 0, packet.length)
                val json = JSONObject(msg)
                if (json.optString("type") == "VOLTMATCH_HUB") {
                    targetHubIp = json.optString("ip")
                    socket.close()
                    consecutiveFailures = 0
                    updateNotification("Streaming to $targetHubIp")
                    return@withContext
                }
                socket.close()
            } catch (e: Exception) {}

            // 2. Subnet scan fallback
            val localIp = getLocalIpAddress()
            if (localIp != null && localIp.contains(".")) {
                val subnet = localIp.substringBeforeLast(".")
                for (i in 1..254) {
                    val testIp = "$subnet.$i"
                    if (testIp == localIp) continue
                    try {
                        val url = URL("http://$testIp:8080/api/discover")
                        val conn = (url.openConnection() as HttpURLConnection).apply {
                            connectTimeout = 120
                            readTimeout = 120
                        }
                        if (conn.responseCode == 200) {
                            val text = conn.inputStream.bufferedReader().readText()
                            val json = JSONObject(text)
                            if (json.optBoolean("hub")) {
                                targetHubIp = testIp
                                conn.disconnect()
                                consecutiveFailures = 0
                                updateNotification("Streaming to $targetHubIp")
                                break
                            }
                        }
                        conn.disconnect()
                    } catch (e: Exception) {}
                }
            }
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

    private fun sendTelemetry(hubIp: String, json: JSONObject) {
        try {
            val url = URL("http://$hubIp:8080/api/push")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = 1500
                readTimeout = 1500
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
            }

            val bytes = json.toString().toByteArray(Charsets.UTF_8)
            conn.outputStream.use { os ->
                os.write(bytes)
                os.flush()
            }

            val code = conn.responseCode
            if (code == 200) {
                consecutiveFailures = 0
                conn.inputStream.close()
            } else {
                conn.errorStream?.close()
                consecutiveFailures++
            }
            conn.disconnect()

            if (consecutiveFailures >= 5) {
                targetHubIp = null
            }
        } catch (e: Exception) {
            consecutiveFailures++
            if (consecutiveFailures >= 5) {
                targetHubIp = null
            }
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
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
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