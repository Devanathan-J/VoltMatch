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
    private var lastNotificationText = ""
    private var failCount = 0

    @Volatile private var isChargerPlugged = false
    @Volatile private var latestBatteryIntent: Intent? = null

    private val deviceName = "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL}"

    // Dedicated Power & Battery Receiver
    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return
            latestBatteryIntent = intent

            when (intent.action) {
                Intent.ACTION_POWER_CONNECTED -> {
                    isChargerPlugged = true
                }
                Intent.ACTION_POWER_DISCONNECTED -> {
                    isChargerPlugged = false
                }
                Intent.ACTION_BATTERY_CHANGED -> {
                    val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
                    val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                    isChargerPlugged = plugged > 0 ||
                                       status == BatteryManager.BATTERY_STATUS_CHARGING ||
                                       status == BatteryManager.BATTERY_STATUS_FULL
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction(Intent.ACTION_BATTERY_CHANGED)
        }
        val stickyIntent = applicationContext.registerReceiver(batteryReceiver, filter)
        if (stickyIntent != null) {
            latestBatteryIntent = stickyIntent
            val plugged = stickyIntent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
            val status = stickyIntent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            isChargerPlugged = plugged > 0 ||
                               status == BatteryManager.BATTERY_STATUS_CHARGING ||
                               status == BatteryManager.BATTERY_STATUS_FULL
        }

        startForeground(NOTIFICATION_ID, buildNotification("Initializing Probe..."))

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VoltMatch::BackgroundProbeWakeLock")
        wakeLock?.acquire(60 * 60 * 1000L)

        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        wifiLock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "VoltMatch::WifiHighPerfLock")
        wifiLock?.acquire()

        VoltMatchTileService.refreshTile(this)
        startAutoDiscoveryAndStreaming()
    }

    private fun startAutoDiscoveryAndStreaming() {
        serviceScope.launch {
            while (isActive && isRunning) {
                val localIp = getLocalIpAddress()
                val hasWifi = localIp != null && localIp.contains(".")
                val hasPower = isChargerPlugged

                // STATE 1: No Wi-Fi
                if (!hasWifi) {
                    targetHubIp = null
                    updateNotification("⚠️ Waiting for Wi-Fi connection...")
                    delay(1000)
                    continue
                }

                // STATE 2: Wi-Fi on, but Charger unplugged
                if (!hasPower) {
                    targetHubIp = null
                    updateNotification("🔌 Connect charger to start streaming")
                    delay(800)
                    continue
                }

                // STATE 3: Verify if current targetHubIp is still alive, otherwise clear and rediscover
                if (targetHubIp != null && !pingHub(targetHubIp!!)) {
                    targetHubIp = null
                }

                // STATE 4: Discover Hub if we don't have a live IP
                if (targetHubIp == null) {
                    updateNotification("Searching for Central Hub...")
                    discoverHub()
                    if (targetHubIp == null) {
                        updateNotification("No Central Hub available")
                        delay(2000)
                        continue
                    }
                }

                // STATE 5: Actively Stream to Verified Live Hub
                val ip = targetHubIp ?: continue
                val payload = sampleBatteryTelemetry()
                val watts = payload.optDouble("watts", 0.0)
                val success = sendTelemetry(ip, payload)

                if (success) {
                    failCount = 0
                    val wStr = String.format("%.1f", watts)
                    updateNotification("⚡ Streaming to $ip ($wStr W)")
                } else {
                    failCount++
                    if (failCount >= 3) {
                        targetHubIp = null
                        failCount = 0
                        updateNotification("No Central Hub available")
                        delay(1500)
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
            // 1. Fast UDP listener (1.2s timeout)
            try {
                val socket = DatagramSocket(8082).apply { soTimeout = 1200 }
                val buf = ByteArray(1024)
                val packet = DatagramPacket(buf, buf.size)
                socket.receive(packet)
                val msg = String(packet.data, 0, packet.length)
                val json = JSONObject(msg)
                if (json.optString("type") == "VOLTMATCH_HUB") {
                    val foundIp = packet.address?.hostAddress ?: json.optString("ip")
                    if (foundIp.isNotEmpty() && pingHub(foundIp)) {
                        targetHubIp = foundIp
                        socket.close()
                        isDiscovering = false
                        return@withContext
                    }
                }
                socket.close()
            } catch (e: Exception) {}

            // 2. Parallel Subnet scan fallback
            val localIp = getLocalIpAddress()
            if (localIp != null && localIp.contains(".")) {
                val subnet = localIp.substringBeforeLast(".")
                for (chunkStart in 1..254 step 30) {
                    if (targetHubIp != null) break
                    coroutineScope {
                        for (i in chunkStart until minOf(chunkStart + 30, 255)) {
                            val testIp = "$subnet.$i"
                            if (testIp == localIp) continue

                            launch {
                                if (pingHub(testIp)) {
                                    targetHubIp = testIp
                                }
                            }
                        }
                    }
                }
            }
            isDiscovering = false
        }
    }

    private fun pingHub(ip: String): Boolean {
        return try {
            val url = URL("http://$ip:8080/api/discover")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 300
                readTimeout = 300
            }
            val ok = conn.responseCode == 200
            conn.disconnect()
            ok
        } catch (e: Exception) {
            false
        }
    }

    private fun sampleBatteryTelemetry(): JSONObject {
        val batteryStatus = latestBatteryIntent
        val rawCurrent = abs(batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW))
        val currentInMA = if (rawCurrent > 10000) rawCurrent / 1000.0 else rawCurrent.toDouble()

        val voltageMv = batteryStatus?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: 0
        val voltageInV = voltageMv / 1000.0

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

        val liveWatts = if (isChargerPlugged) voltageInV * (currentInMA / 1000.0) else 0.0

        return JSONObject().apply {
            put("id", "probe_tile_${Build.MODEL.replace(" ", "_")}")
            put("name", deviceName)
            put("watts", liveWatts)
            put("currentMA", currentInMA)
            put("voltageV", voltageInV)
            put("batteryPct", batteryPct)
            put("tempC", tempC)
            put("maxChargingWatts", maxWatts)
            put("isCharging", isChargerPlugged)
        }
    }

    private val batteryManager by lazy { getSystemService(Context.BATTERY_SERVICE) as BatteryManager }

    private fun sendTelemetry(hubIp: String, json: JSONObject): Boolean {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL("http://$hubIp:8080/api/push")
            val jsonBytes = json.toString().toByteArray(Charsets.UTF_8)

            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                doInput = true
                useCaches = false
                connectTimeout = 1000
                readTimeout = 1000
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("Accept", "application/json")
                setFixedLengthStreamingMode(jsonBytes.size)
            }

            conn.outputStream.use { os ->
                os.write(jsonBytes)
                os.flush()
            }

            val code = conn.responseCode
            if (code in 200..299) {
                conn.inputStream?.bufferedReader()?.use { it.readText() }
                true
            } else {
                false
            }
        } catch (e: Exception) {
            false
        } finally {
            try {
                conn?.disconnect()
            } catch (e: Exception) {}
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
            .setContentTitle("⚡ VoltMatch Probe")
            .setContentText(statusText)
            .setSmallIcon(R.drawable.ic_qs_voltmatch)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(statusText: String) {
        if (statusText == lastNotificationText) return
        lastNotificationText = statusText
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(statusText))
    }

    override fun onDestroy() {
        isRunning = false
        serviceScope.cancel()

        try {
            applicationContext.unregisterReceiver(batteryReceiver)
        } catch (e: Exception) {}

        if (wakeLock?.isHeld == true) wakeLock?.release()
        if (wifiLock?.isHeld == true) wifiLock?.release()

        VoltMatchTileService.refreshTile(this)
        super.onDestroy()
    }

    companion object {
        const val CHANNEL_ID = "voltmatch_probe_channel"
        const val NOTIFICATION_ID = 2044
        var isRunning = false
    }
}