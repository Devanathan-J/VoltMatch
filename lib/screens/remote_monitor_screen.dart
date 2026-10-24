import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RemoteMonitorScreen extends StatefulWidget {
  const RemoteMonitorScreen({super.key});

  @override
  State<RemoteMonitorScreen> createState() => _RemoteMonitorScreenState();
}

class _RemoteMonitorScreenState extends State<RemoteMonitorScreen> {
  static const platform = MethodChannel('com.voltmatch/hardware');

  // Mode: true = Central Hub, false = Remote Probe
  bool isHostMode = true;
  bool enable80AlertSound = true; // Two-way synced sound toggle

  bool isRunning = false;
  String broadcastUrl = '';
  String cachedLocalIp = '127.0.0.1';
  final TextEditingController hubIpController = TextEditingController();
  final TextEditingController nicknameController = TextEditingController();

  HttpServer? _server;
  Timer? _fastTimer;
  HttpClient? _probeClient;

  // Multi-device telemetry repository on the Hub
  final Map<String, Map<String, dynamic>> _connectedDevices = {};

  // Self telemetry
  String deviceName = 'Android Device';
  double currentMA = 0.0;
  double voltageV = 0.0;
  double liveWatts = 0.0;
  double tempC = 0.0;
  double maxWatts = 0.0;
  int batteryPct = 0;
  bool isCharging = false;

  @override
  void initState() {
    super.initState();
    _resolveLocalIp();
  }

  @override
  void dispose() {
    _stopSession();
    hubIpController.dispose();
    nicknameController.dispose();
    super.dispose();
  }

  Future<void> _resolveLocalIp() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            setState(() {
              cachedLocalIp = addr.address;
            });
            return;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchSelfStats() async {
    try {
      final Map<dynamic, dynamic> res = await platform.invokeMethod('getLivePowerStats');
      if (mounted) {
        final charging = res['isCharging'] as bool;
        final cMA = (res['currentMA'] as num).toDouble();
        final vV = (res['voltageV'] as num).toDouble();

        setState(() {
          deviceName = res['deviceName'] ?? 'Device';
          isCharging = charging;
          voltageV = vV;
          batteryPct = res['batteryPct'] as int;
          tempC = (res['tempC'] as num).toDouble();
          maxWatts = (res['maxChargingWatts'] as num).toDouble();

          if (!charging) {
            currentMA = 0.0;
            liveWatts = 0.0;
          } else {
            currentMA = cMA;
            liveWatts = voltageV * (currentMA / 1000.0);
          }

          if (isHostMode) {
            final effectiveName = nicknameController.text.trim().isNotEmpty
                ? nicknameController.text.trim()
                : deviceName;

            _connectedDevices['self'] = {
              'id': 'self',
              'name': effectiveName,
              'watts': liveWatts,
              'currentMA': currentMA,
              'voltageV': voltageV,
              'batteryPct': batteryPct,
              'tempC': tempC,
              'maxChargingWatts': maxWatts,
              'isCharging': isCharging,
              'lastSeen': DateTime.now().millisecondsSinceEpoch,
            };
          }
        });
      }
    } catch (_) {}
  }

  // START: Host Central Hub
  Future<void> _startHost() async {
    await _resolveLocalIp();
    await platform.invokeMethod('acquireWakeLock');

    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
    setState(() {
      isRunning = true;
      broadcastUrl = 'http://$cachedLocalIp:8080';
    });

    _fastTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      _fetchSelfStats();
      _pruneStaleDevices();
    });

    _server!.listen((HttpRequest req) async {
      req.response.headers.add('Access-Control-Allow-Origin', '*');
      req.response.headers.add('Access-Control-Allow-Headers', '*');
      req.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');

      if (req.method == 'OPTIONS') {
        req.response.statusCode = HttpStatus.ok;
        await req.response.close();
        return;
      }

      if (req.uri.path == '/api/stats') {
        final list = _connectedDevices.values.toList();
        req.response
          ..headers.contentType = ContentType.json
          ..write(json.encode({
            'devices': list,
            'soundEnabled': enable80AlertSound,
          }))
          ..close();
      } else if (req.uri.path == '/api/set-sound' && req.method == 'POST') {
        // Two-way sync: browser changes sound setting
        try {
          final body = await utf8.decoder.bind(req).join();
          final data = json.decode(body) as Map<String, dynamic>;
          final enabled = data['enabled'] as bool;
          if (mounted) {
            setState(() {
              enable80AlertSound = enabled;
            });
          }
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(json.encode({'soundEnabled': enable80AlertSound}))
            ..close();
        } catch (_) {
          req.response.statusCode = HttpStatus.badRequest;
          await req.response.close();
        }
      } else if (req.uri.path == '/api/push' && req.method == 'POST') {
        try {
          final body = await utf8.decoder.bind(req).join();
          final data = json.decode(body) as Map<String, dynamic>;
          final id = data['id'] ?? 'probe_${DateTime.now().millisecondsSinceEpoch}';
          data['lastSeen'] = DateTime.now().millisecondsSinceEpoch;
          _connectedDevices[id] = data;
          req.response
            ..statusCode = HttpStatus.ok
            ..write(json.encode({'status': 'ok'}))
            ..close();
        } catch (_) {
          req.response.statusCode = HttpStatus.badRequest;
          await req.response.close();
        }
      } else {
        req.response
          ..headers.contentType = ContentType.html
          ..write(_generateMultiDeviceHtmlDashboard())
          ..close();
      }
    });
  }

  void _pruneStaleDevices() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _connectedDevices.removeWhere((key, val) => key != 'self' && (now - (val['lastSeen'] as int)) > 5000);
  }

  // START: Join as Remote Probe
  Future<void> _startProbe() async {
    var targetIp = hubIpController.text.trim();
    // Automatically cleans "http://", "https://", and ":8080" if pasted!
    targetIp = targetIp.replaceAll('http://', '').replaceAll('https://', '');
    if (targetIp.contains(':')) {
      targetIp = targetIp.split(':')[0];
    }
    if (targetIp.endsWith('/')) {
      targetIp = targetIp.substring(0, targetIp.length - 1);
    }

    await platform.invokeMethod('acquireWakeLock');
    _probeClient = HttpClient()..connectionTimeout = const Duration(seconds: 1);

    setState(() {
      isRunning = true;
      broadcastUrl = 'Streaming to http://$targetIp:8080';
    });

    final selfId = 'probe_${Platform.operatingSystem}_${cachedLocalIp.replaceAll('.', '_')}';

    _fastTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      await _fetchSelfStats();
      try {
        final effectiveName = nicknameController.text.trim().isNotEmpty
            ? nicknameController.text.trim()
            : deviceName;

        final req = await _probeClient!.postUrl(Uri.parse('http://$targetIp:8080/api/push'));
        req.headers.contentType = ContentType.json;
        req.write(json.encode({
          'id': selfId,
          'name': effectiveName,
          'watts': liveWatts,
          'currentMA': currentMA,
          'voltageV': voltageV,
          'batteryPct': batteryPct,
          'tempC': tempC,
          'maxChargingWatts': maxWatts,
          'isCharging': isCharging,
        }));
        final res = await req.close();
        await res.drain();
      } catch (_) {}
    });
  }

  Future<void> _stopSession() async {
    _fastTimer?.cancel();
    _probeClient?.close(force: true);
    await _server?.close(force: true);
    await platform.invokeMethod('releaseWakeLock');

    if (mounted) {
      setState(() {
        isRunning = false;
        broadcastUrl = '';
        _connectedDevices.clear();
        liveWatts = 0.0;
        currentMA = 0.0;
        isCharging = false;
      });
    }
  }

  void _copyLink() {
    if (broadcastUrl.isEmpty) return;
    Clipboard.setData(ClipboardData(text: broadcastUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied: $broadcastUrl'),
        backgroundColor: const Color(0xFF22BFA2),
      ),
    );
  }

  String _generateMultiDeviceHtmlDashboard() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>VoltMatch Multi-Device Dashboard</title>
  <style>
    :root {
      --bg: #101419;
      --card-bg: #161D23;
      --card-border: rgba(255,255,255,0.08);
      --accent: #22BFA2;
      --accent-bright: #3DDDB5;
      --warn: #F5B544;
      --danger: #EF6464;
      --text: #FFFFFF;
      --subtext: #A7B0B9;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      min-height: 100vh;
      padding: 20px;
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    header {
      width: 100%;
      max-width: 1300px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 24px;
      padding-bottom: 12px;
      border-bottom: 1px solid var(--card-border);
    }
    .brand { display: flex; align-items: center; gap: 10px; font-weight: 800; font-size: 20px; }
    .bolt { color: var(--accent); font-size: 24px; }
    .header-actions { display: flex; align-items: center; gap: 10px; }
    .status-badge {
      background: rgba(34,191,162,0.15);
      color: var(--accent);
      padding: 6px 14px;
      border-radius: 20px;
      font-size: 13px;
      font-weight: 600;
      transition: all 0.3s ease;
    }
    .sound-btn {
      background: rgba(255,255,255,0.08);
      color: var(--text);
      border: 1px solid var(--card-border);
      padding: 6px 14px;
      border-radius: 20px;
      font-size: 12px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s ease;
    }

    .grid {
      width: 100%;
      max-width: 1300px;
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 18px;
      transition: all 0.3s ease;
    }
    .grid.single-device { max-width: 480px; }

    .device-card {
      background: var(--card-bg);
      border-radius: 20px;
      border: 1.5px solid var(--card-border);
      padding: 20px;
      display: flex;
      flex-direction: column;
      position: relative;
      overflow: hidden;
      box-shadow: 0 8px 32px rgba(0,0,0,0.4);
      transition: all 0.2s ease;
    }
    .device-card.charging { border-color: rgba(34,191,162,0.35); }

    .card-top { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 12px; }
    .device-title { font-size: 16px; font-weight: 700; color: #fff; max-width: 70%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .device-status { font-size: 11px; font-weight: 700; padding: 4px 10px; border-radius: 12px; text-transform: uppercase; }
    .status-charging { background: rgba(46,204,145,0.15); color: #2ECC91; }
    .status-idle { background: rgba(255,255,255,0.08); color: var(--subtext); }

    .ceiling-tag { font-size: 11px; color: var(--accent-bright); font-weight: 600; margin-bottom: 2px; }
    .watts-display { font-size: 46px; font-weight: 800; color: var(--accent); letter-spacing: -1px; line-height: 1; margin: 6px 0; }
    .watts-display.idle { color: var(--subtext); }
    .elec-specs { font-size: 13px; color: var(--subtext); margin-bottom: 14px; }

    .chart-container {
      width: 100%;
      height: 70px;
      background: rgba(0,0,0,0.25);
      border-radius: 10px;
      overflow: hidden;
      margin-bottom: 14px;
      border: 1px solid rgba(255,255,255,0.03);
    }
    canvas { width: 100%; height: 100%; display: block; }

    .stats-row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: auto; }
    .pill { background: rgba(0,0,0,0.2); border-radius: 10px; padding: 8px 12px; border: 1px solid rgba(255,255,255,0.03); }
    .pill-label { font-size: 11px; color: var(--subtext); }
    .pill-val { font-size: 14px; font-weight: 700; margin-top: 2px; }

    .alert-80-badge {
      background: rgba(245,181,68,0.2);
      border: 1px solid var(--warn);
      color: var(--warn);
      font-size: 12px;
      font-weight: 700;
      padding: 6px 10px;
      border-radius: 10px;
      margin-bottom: 10px;
      text-align: center;
      animation: pulse 1.5s infinite;
    }
    @keyframes pulse { 0% { opacity: 0.8; } 50% { opacity: 1; } 100% { opacity: 0.8; } }

    .disconnect-card {
      background: var(--card-bg);
      border-radius: 20px;
      border: 2px solid var(--danger);
      padding: 40px 24px;
      text-align: center;
      grid-column: 1 / -1;
      max-width: 480px;
      margin: 40px auto;
      box-shadow: 0 10px 40px rgba(0,0,0,0.6);
    }
    .no-devices { text-align: center; padding: 60px 20px; color: var(--subtext); font-size: 16px; grid-column: 1 / -1; }
  </style>
</head>
<body>
  <header>
    <div class="brand">
      <span class="bolt">⚡</span>
      <span>VoltMatch Monitor Hub</span>
    </div>
    <div class="header-actions">
      <button id="sound-toggle" class="sound-btn" onclick="toggleSound()">🔔 Sound: ON</button>
      <div class="status-badge" id="hub-count">Connecting...</div>
    </div>
  </header>

  <div class="grid" id="devices-grid">
    <div class="no-devices">Connecting to VoltMatch Central Hub...</div>
  </div>

  <script>
    let audioCtx = null;
    let soundEnabled = true;
    let isSyncing = false;
    let lastTingTime = 0;
    const deviceHistories = {};

    function updateSoundUi(enabled) {
      const btn = document.getElementById('sound-toggle');
      if (!btn) return;
      btn.innerText = enabled ? '🔔 Sound: ON' : '🔕 Sound: OFF';
      btn.style.borderColor = enabled ? 'var(--accent)' : 'rgba(255,255,255,0.15)';
      btn.style.color = enabled ? 'var(--accent-bright)' : 'var(--subtext)';
    }

    // Two-Way Sync: User clicks in the browser
    async function toggleSound() {
      const newState = !soundEnabled;
      soundEnabled = newState;
      isSyncing = true;
      updateSoundUi(soundEnabled);

      try {
        const res = await fetch('/api/set-sound', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ enabled: newState })
        });
        const d = await res.json();
        soundEnabled = d.soundEnabled;
        updateSoundUi(soundEnabled);
      } catch(e) {}
      
      // Release sync lock after 600ms
      setTimeout(() => { isSyncing = false; }, 600);
    }

    function playMildTing() {
      if (!soundEnabled) return;
      try {
        if (!audioCtx) {
          audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        }
        if (audioCtx.state === 'suspended') {
          audioCtx.resume();
        }
        const now = audioCtx.currentTime;

        // Mild high crystal bell tone (1760 Hz - A6)
        const osc1 = audioCtx.createOscillator();
        const gain1 = audioCtx.createGain();
        osc1.type = 'sine';
        osc1.frequency.setValueAtTime(1760, now);
        gain1.gain.setValueAtTime(0.14, now);
        gain1.gain.exponentialRampToValueAtTime(0.0001, now + 0.8);
        osc1.connect(gain1);
        gain1.connect(audioCtx.destination);
        osc1.start(now);
        osc1.stop(now + 0.8);

        // Gentle harmonic overtone (2637 Hz - E7)
        const osc2 = audioCtx.createOscillator();
        const gain2 = audioCtx.createGain();
        osc2.type = 'sine';
        osc2.frequency.setValueAtTime(2637, now);
        gain2.gain.setValueAtTime(0.09, now);
        gain2.gain.exponentialRampToValueAtTime(0.0001, now + 0.6);
        osc2.connect(gain2);
        gain2.connect(audioCtx.destination);
        osc2.start(now);
        osc2.stop(now + 0.6);
      } catch(e) {}
    }

    document.addEventListener('click', () => {
      if (audioCtx && audioCtx.state === 'suspended') audioCtx.resume();
    }, { once: true });

    function drawSparkline(canvasId, historyData) {
      const cvs = document.getElementById(canvasId);
      if (!cvs) return;
      const ctx = cvs.getContext('2d');
      const w = cvs.width = cvs.offsetWidth;
      const h = cvs.height = cvs.offsetHeight;
      ctx.clearRect(0, 0, w, h);

      const maxVal = Math.max(20, ...historyData) * 1.15;
      ctx.strokeStyle = '#22BFA2';
      ctx.lineWidth = 2.2;
      ctx.beginPath();
      for (let i = 0; i < historyData.length; i++) {
        const x = (i / (historyData.length - 1)) * w;
        const y = h - ((historyData[i] / maxVal) * (h - 8)) - 4;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.stroke();
    }

    async function pollHub() {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 1200);
        const res = await fetch('/api/stats', { signal: controller.signal });
        clearTimeout(timeoutId);

        if (!res.ok) throw new Error("Offline");
        const payload = await res.json();
        const devices = payload.devices || [];

        // Two-Way Sync: If phone changed the switch, browser updates instantly!
        if (!isSyncing && payload.soundEnabled !== undefined) {
          soundEnabled = payload.soundEnabled;
          updateSoundUi(soundEnabled);
        }

        const grid = document.getElementById('devices-grid');
        const badge = document.getElementById('hub-count');
        badge.style.background = 'rgba(34,191,162,0.15)';
        badge.style.color = '#22BFA2';
        badge.innerText = devices.length + (devices.length === 1 ? ' Device Active' : ' Devices Active');

        if (devices.length <= 1) {
          grid.classList.add('single-device');
        } else {
          grid.classList.remove('single-device');
        }

        if (devices.length === 0) {
          grid.innerHTML = '<div class="no-devices">No active devices broadcasting on this hub.<br>Connect your phone and start streaming!</div>';
          return;
        }

        // Check if any device has 80%+ and is charging
        const has80Charging = devices.some(d => d.batteryPct >= 80 && d.isCharging);
        const now = Date.now();
        if (has80Charging && soundEnabled) {
          // Mild chime every 10 seconds in the browser only!
          if (now - lastTingTime >= 10000) {
            lastTingTime = now;
            playMildTing();
          }
        } else {
          lastTingTime = 0;
        }

        let html = '';
        devices.forEach((d) => {
          const isChg = d.isCharging;
          const wText = isChg ? d.watts.toFixed(1) + ' W' : '0.0 W';
          const statusCls = isChg ? 'status-charging' : 'status-idle';
          const statusText = isChg ? '⚡ Charging' : 'Unplugged';
          const tempColor = d.tempC > 40 ? '#EF6464' : (d.tempC > 36 ? '#F5B544' : '#2ECC91');
          const isAt80 = d.batteryPct >= 80 && isChg;

          html += `
            <div class="device-card \${isChg ? 'charging' : ''}">
              \${isAt80 ? '<div class="alert-80-badge">🔔 80% Reached — Unplug Recommended!</div>' : ''}
              <div class="card-top">
                <div class="device-title" title="\${d.name}">\${d.name}</div>
                <div class="device-status \${statusCls}">\${statusText}</div>
              </div>
              \${d.maxChargingWatts > 0 ? '<div class="ceiling-tag">⚡ Hardware Limit: ' + Math.round(d.maxChargingWatts) + 'W</div>' : ''}
              <div class="watts-display \${isChg ? '' : 'idle'}">\${wText}</div>
              <div class="elec-specs">\${Math.round(d.currentMA)} mA • \${d.voltageV.toFixed(2)} V</div>
              
              <div class="chart-container">
                <canvas id="cvs_\${d.id}"></canvas>
              </div>

              <div class="stats-row">
                <div class="pill">
                  <div class="pill-label">Battery Level</div>
                  <div class="pill-val">\${d.batteryPct}%</div>
                </div>
                <div class="pill">
                  <div class="pill-label">Temperature</div>
                  <div class="pill-val" style="color: \${tempColor}">\${d.tempC.toFixed(1)} °C</div>
                </div>
              </div>
            </div>
          `;
        });

        grid.innerHTML = html;

        devices.forEach((d) => {
          if (!deviceHistories[d.id]) {
            deviceHistories[d.id] = new Array(25).fill(0);
          }
          deviceHistories[d.id].push(d.isCharging ? d.watts : 0);
          deviceHistories[d.id].shift();
          drawSparkline('cvs_' + d.id, deviceHistories[d.id]);
        });

      } catch(e) {
        // Instant Disconnect Card
        const grid = document.getElementById('devices-grid');
        const badge = document.getElementById('hub-count');
        badge.innerText = 'Hub Disconnected';
        badge.style.background = 'rgba(239,100,100,0.15)';
        badge.style.color = '#EF6464';

        grid.innerHTML = `
          <div class="disconnect-card">
            <div style="font-size: 42px; margin-bottom: 12px;">🛑</div>
            <div style="font-size: 22px; font-weight: 800; color: #EF6464; margin-bottom: 8px;">Broadcast Stopped</div>
            <div style="color: var(--subtext); font-size: 14px; line-height: 1.5;">
              The phone has stopped broadcasting.<br>
              Tap <b>Start</b> on your phone to resume live telemetry.
            </div>
          </div>
        `;
      }
    }

    setInterval(pollHub, 300);
    pollHub();
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Multi-Device Charging Hub')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // MODE TOGGLE TABS
              if (!isRunning)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161D23),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Central Hub (Host)')),
                          selected: isHostMode,
                          selectedColor: const Color(0xFF22BFA2),
                          labelStyle: TextStyle(
                            color: isHostMode ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (val) => setState(() => isHostMode = true),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Join as Probe')),
                          selected: !isHostMode,
                          selectedColor: const Color(0xFF22BFA2),
                          labelStyle: TextStyle(
                            color: !isHostMode ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (val) => setState(() => isHostMode = false),
                        ),
                      ),
                    ],
                  ),
                ),

              // SETUP CARD
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C252C),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isRunning ? const Color(0xFF22BFA2) : Colors.white12,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      isHostMode ? Icons.hub : Icons.sensors,
                      size: 44,
                      color: isRunning ? const Color(0xFF22BFA2) : Colors.grey,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isHostMode ? 'Central Dashboard Hub' : 'Remote Probe Streamer',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isHostMode
                          ? 'Hosts the single dashboard webpage. Connect up to 10 phones to this single URL!'
                          : 'Sends this phone\'s live power data to the Hub Phone over Wi-Fi.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFA7B0B9), fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    // Custom Nickname input
                    if (!isRunning) ...[
                      TextField(
                        controller: nicknameController,
                        decoration: InputDecoration(
                          labelText: 'Device Nickname (Optional)',
                          hintText: 'e.g. My iQOO Z6 or Mom\'s Phone',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // In Probe mode: Target Hub IP input
                    if (!isHostMode && !isRunning) ...[
                      TextField(
                        controller: hubIpController,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: 'Hub Phone IP Address',
                          hintText: 'e.g. $cachedLocalIp',
                          prefixIcon: const Icon(Icons.wifi, size: 20),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 80% Sound Alert Toggle Switch (Two-Way Synced)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        '80% Charge Sound Alert',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Chimes in browser every 10s when battery reaches 80%+',
                        style: TextStyle(fontSize: 12, color: Color(0xFFA7B0B9)),
                      ),
                      value: enable80AlertSound,
                      activeColor: const Color(0xFF22BFA2),
                      onChanged: (val) {
                        setState(() => enable80AlertSound = val);
                      },
                    ),

                    // Running Link Box
                    if (isRunning) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101419),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF22BFA2)),
                        ),
                        child: SelectableText(
                          broadcastUrl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF3DDDB5),
                          ),
                        ),
                      ),
                      if (isHostMode) ...[
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF22BFA2).withOpacity(0.15),
                            foregroundColor: const Color(0xFF22BFA2),
                            side: const BorderSide(color: Color(0xFF22BFA2)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy Single Hub URL'),
                          onPressed: _copyLink,
                        ),
                      ],
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ACTION BUTTON
              if (!isRunning)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22BFA2),
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    isHostMode ? 'Start Single-IP Central Hub' : 'Connect to Central Hub',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  onPressed: isHostMode ? _startHost : _startProbe,
                )
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF6464),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Session', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  onPressed: _stopSession,
                ),

              const SizedBox(height: 24),

              // MULTI-DEVICE INSTRUCTIONS CARD
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF161D23),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.devices, color: Color(0xFF3DDDB5), size: 20),
                        SizedBox(width: 8),
                        Text('How to view all phones on 1 IP:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    SizedBox(height: 10),
                    Text('1. On Phone 1: Select "Central Hub", tap Start. Copy the URL.', style: TextStyle(color: Color(0xFFA7B0B9), fontSize: 12.5, height: 1.4)),
                    SizedBox(height: 6),
                    Text('2. On Phone 2..10: Select "Join as Probe", enter Phone 1\'s IP, tap Connect.', style: TextStyle(color: Color(0xFFA7B0B9), fontSize: 12.5, height: 1.4)),
                    SizedBox(height: 6),
                    Text('3. Open the single URL in Chrome: All phones appear together in a dynamic auto-resizing grid!', style: TextStyle(color: Color(0xFF3DDDB5), fontSize: 12.5, height: 1.4, fontWeight: FontWeight.bold)),
                    SizedBox(height: 6),
                    Text('4. Sound is heard through the browser only. Toggling the sound switch in the app OR on the webpage keeps both 100% in sync!', style: TextStyle(color: Color(0xFFA7B0B9), fontSize: 12.5, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}