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

  bool isHostMode = true;
  bool enable80AlertSound = true;
  bool isRunning = false;
  bool showManualIpInput = false;

  String broadcastUrl = '';
  String cachedLocalIp = '127.0.0.1';
  final TextEditingController hubIpController = TextEditingController();
  final TextEditingController nicknameController = TextEditingController();

  // Auto-Discovery
  bool isSearchingForHub = false;
  String? discoveredHubName;
  String? discoveredHubIp;
  RawDatagramSocket? _udpBeaconSocket;
  RawDatagramSocket? _udpListenSocket;
  Timer? _beaconTimer;

  HttpServer? _server;
  Timer? _fastTimer;
  HttpClient? _probeClient;

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
    _resolveLocalIp().then((_) {
      if (!isHostMode) {
        _startAutoDiscovery();
      }
    });
  }

  @override
  void dispose() {
    _stopSession();
    _stopDiscovery();
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

  // ─────────────────────────────────────────────────────────────
  // AUTO-DISCOVERY ENGINE
  // ─────────────────────────────────────────────────────────────

  Future<void> _startUdpBeacon() async {
    try {
      _udpBeaconSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpBeaconSocket?.broadcastEnabled = true;

      _beaconTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!isRunning || !isHostMode) return;
        final effectiveName = nicknameController.text.trim().isNotEmpty
            ? nicknameController.text.trim()
            : deviceName;

        final msg = utf8.encode(json.encode({
          'type': 'VOLTMATCH_HUB',
          'ip': cachedLocalIp,
          'name': effectiveName,
        }));
        _udpBeaconSocket?.send(msg, InternetAddress('255.255.255.255'), 8082);
      });
    } catch (_) {}
  }

  Future<void> _startAutoDiscovery() async {
    if (isRunning) return;
    setState(() {
      isSearchingForHub = true;
      discoveredHubIp = null;
      discoveredHubName = null;
    });

    try {
      _udpListenSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        8082,
        reuseAddress: true,
        reusePort: true,
      );
      _udpListenSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpListenSocket?.receive();
          if (datagram != null) {
            try {
              final str = utf8.decode(datagram.data);
              final data = json.decode(str) as Map<String, dynamic>;
              if (data['type'] == 'VOLTMATCH_HUB' && data['ip'] != null) {
                _onHubFound(data['ip'], data['name'] ?? 'VoltMatch Hub');
              }
            } catch (_) {}
          }
        }
      });
    } catch (_) {}

    _scanSubnetForHub();
  }

  Future<void> _scanSubnetForHub() async {
    if (cachedLocalIp == '127.0.0.1') return;
    final parts = cachedLocalIp.split('.');
    if (parts.length != 4) return;
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 350);

    const chunkSize = 40;
    for (int i = 1; i <= 254; i += chunkSize) {
      if (discoveredHubIp != null || !mounted || !isSearchingForHub) break;
      final futures = <Future>[];
      for (int j = i; j < i + chunkSize && j <= 254; j++) {
        final target = '$subnet.$j';
        if (target == cachedLocalIp) continue;

        futures.add(() async {
          try {
            final req = await client.getUrl(Uri.parse('http://$target:8080/api/discover'));
            final res = await req.close();
            if (res.statusCode == HttpStatus.ok) {
              final body = await utf8.decoder.bind(res).join();
              final data = json.decode(body) as Map<String, dynamic>;
              if (data['hub'] == true) {
                _onHubFound(target, data['name'] ?? 'VoltMatch Hub');
              }
            }
          } catch (_) {}
        }());
      }
      await Future.wait(futures);
    }
    client.close(force: true);

    if (mounted && discoveredHubIp == null) {
      setState(() {
        isSearchingForHub = false;
      });
    }
  }

  void _onHubFound(String ip, String name) {
    if (!mounted || discoveredHubIp != null) return;
    setState(() {
      discoveredHubIp = ip;
      discoveredHubName = name;
      hubIpController.text = ip;
      isSearchingForHub = false;
    });
    _stopDiscovery();
  }

  void _stopDiscovery() {
    _beaconTimer?.cancel();
    _udpBeaconSocket?.close();
    _udpListenSocket?.close();
    _udpBeaconSocket = null;
    _udpListenSocket = null;
  }

  // ─────────────────────────────────────────────────────────────
  // TELEMETRY SAMPLING
  // ─────────────────────────────────────────────────────────────

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

  // START: Host
  Future<void> _startHost() async {
    _stopDiscovery();
    await _resolveLocalIp();
    await platform.invokeMethod('acquireWakeLock');

    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
    setState(() {
      isRunning = true;
      broadcastUrl = 'http://$cachedLocalIp:8080';
    });

    _startUdpBeacon();

    _fastTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
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

      if (req.uri.path == '/api/discover') {
        final effectiveName = nicknameController.text.trim().isNotEmpty
            ? nicknameController.text.trim()
            : deviceName;

        req.response
          ..headers.contentType = ContentType.json
          ..write(json.encode({
            'hub': true,
            'ip': cachedLocalIp,
            'name': effectiveName,
          }))
          ..close();
      } else if (req.uri.path == '/api/stats') {
        final list = _connectedDevices.values.toList();
        req.response
          ..headers.contentType = ContentType.json
          ..write(json.encode({
            'devices': list,
            'soundEnabled': enable80AlertSound,
          }))
          ..close();
      } else if (req.uri.path == '/api/set-sound' && req.method == 'POST') {
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

  // START: Probe
  Future<void> _startProbe() async {
    _stopDiscovery();

    var targetIp = hubIpController.text.trim();
    targetIp = targetIp.replaceAll('http://', '').replaceAll('https://', '');
    if (targetIp.contains(':')) targetIp = targetIp.split(':')[0];
    if (targetIp.endsWith('/')) targetIp = targetIp.substring(0, targetIp.length - 1);

    if (targetIp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Hub selected or detected')),
      );
      return;
    }

    await platform.invokeMethod('acquireWakeLock');
    _probeClient = HttpClient()..connectionTimeout = const Duration(seconds: 1);

    setState(() {
      isRunning = true;
      broadcastUrl = 'Streaming to $targetIp';
    });

    final selfId = 'probe_${Platform.operatingSystem}_${cachedLocalIp.replaceAll('.', '_')}';

    _fastTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
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

    if (!isHostMode) {
      _startAutoDiscovery();
    }
  }

  void _copyLink() {
    if (broadcastUrl.isEmpty) return;
    Clipboard.setData(ClipboardData(text: broadcastUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Hub link copied! Open it in any browser.'),
        backgroundColor: Color(0xFF22BFA2),
      ),
    );
  }

  String _generateMultiDeviceHtmlDashboard() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>VoltMatch Telemetry</title>
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
      padding: 24px 20px;
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    header {
      width: 100%;
      max-width: 1200px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 24px;
      padding-bottom: 14px;
      border-bottom: 1px solid var(--card-border);
    }
    .brand { display: flex; align-items: center; gap: 10px; font-weight: 800; font-size: 20px; }
    .bolt { color: var(--accent); font-size: 24px; }
    .header-actions { display: flex; align-items: center; gap: 10px; }
    .status-badge {
      background: rgba(34,191,162,0.12);
      color: var(--accent);
      padding: 6px 14px;
      border-radius: 20px;
      font-size: 13px;
      font-weight: 600;
      transition: all 0.3s ease;
    }
    .sound-btn {
      background: rgba(255,255,255,0.06);
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
      max-width: 1200px;
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(310px, 1fr));
      gap: 16px;
    }
    .grid.single-device { max-width: 440px; }
    .device-card {
      background: var(--card-bg);
      border-radius: 20px;
      border: 1.5px solid var(--card-border);
      padding: 22px;
      display: flex;
      flex-direction: column;
      position: relative;
      box-shadow: 0 10px 30px rgba(0,0,0,0.4);
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
      height: 65px;
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
    }
    .disconnect-card {
      background: var(--card-bg);
      border-radius: 20px;
      border: 2px solid var(--danger);
      padding: 40px 24px;
      text-align: center;
      grid-column: 1 / -1;
      max-width: 440px;
      margin: 40px auto;
    }
    .no-devices { text-align: center; padding: 60px 20px; color: var(--subtext); font-size: 15px; grid-column: 1 / -1; }
  </style>
</head>
<body>
  <header>
    <div class="brand"><span class="bolt">⚡</span><span>VoltMatch</span></div>
    <div class="header-actions">
      <button id="sound-toggle" class="sound-btn" onclick="toggleSound()">🔔 Sound: ON</button>
      <div class="status-badge" id="hub-count">Connecting...</div>
    </div>
  </header>

  <div class="grid" id="devices-grid">
    <div class="no-devices">Searching for connected devices...</div>
  </div>

  <script>
    let audioCtx = null;
    let soundEnabled = true;
    let isSyncing = false;
    let lastTingTime = 0;
    let consecutiveErrors = 0; // Professional-grade 3-strike network resilience
    const deviceHistories = {};

    // Pre-warm AudioContext on user interaction so audio never blocks the network thread
    function getAudioContext() {
      if (!audioCtx) {
        audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      }
      if (audioCtx && audioCtx.state === 'suspended') {
        audioCtx.resume();
      }
      return audioCtx;
    }

    document.addEventListener('click', () => { getAudioContext(); }, { once: true });

    function updateSoundUi(enabled) {
      const btn = document.getElementById('sound-toggle');
      if (!btn) return;
      btn.innerText = enabled ? '🔔 Sound: ON' : '🔕 Sound: OFF';
      btn.style.color = enabled ? 'var(--accent-bright)' : 'var(--subtext)';
    }

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
      setTimeout(() => { isSyncing = false; }, 600);
    }

    // Decoupled, non-blocking chime synthesizer
    function playMildTing() {
      if (!soundEnabled) return;
      try {
        const ctx = getAudioContext();
        if (!ctx) return;
        const now = ctx.currentTime;

        const osc1 = ctx.createOscillator();
        const gain1 = ctx.createGain();
        osc1.type = 'sine';
        osc1.frequency.setValueAtTime(1760, now);
        gain1.gain.setValueAtTime(0.14, now);
        gain1.gain.exponentialRampToValueAtTime(0.0001, now + 0.8);
        osc1.connect(gain1);
        gain1.connect(ctx.destination);
        osc1.start(now);
        osc1.stop(now + 0.8);

        const osc2 = ctx.createOscillator();
        const gain2 = ctx.createGain();
        osc2.type = 'sine';
        osc2.frequency.setValueAtTime(2637, now);
        gain2.gain.setValueAtTime(0.09, now);
        gain2.gain.exponentialRampToValueAtTime(0.0001, now + 0.6);
        osc2.connect(gain2);
        gain2.connect(ctx.destination);
        osc2.start(now);
        osc2.stop(now + 0.6);
      } catch(e) {}
    }

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
        // Generous 2.5s network timeout ensures Wi-Fi micro-delays never trigger a false disconnect
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 2500);
        const res = await fetch('/api/stats', { signal: controller.signal });
        clearTimeout(timeoutId);

        if (!res.ok) throw new Error("Offline");
        const payload = await res.json();
        const devices = payload.devices || [];

        // Connection is healthy: reset error counter immediately
        consecutiveErrors = 0;

        if (!isSyncing && payload.soundEnabled !== undefined) {
          soundEnabled = payload.soundEnabled;
          updateSoundUi(soundEnabled);
        }

        const grid = document.getElementById('devices-grid');
        const badge = document.getElementById('hub-count');
        badge.style.background = 'rgba(34,191,162,0.12)';
        badge.style.color = '#22BFA2';
        badge.innerText = devices.length + (devices.length === 1 ? ' Device' : ' Devices');

        if (devices.length <= 1) {
          grid.classList.add('single-device');
        } else {
          grid.classList.remove('single-device');
        }

        if (devices.length === 0) {
          grid.innerHTML = '<div class="no-devices">No active devices broadcasting.<br>Connect your phone to stream live data.</div>';
          return;
        }

        // Check 80% charge threshold
        const has80Charging = devices.some(d => d.batteryPct >= 80 && d.isCharging);
        const now = Date.now();
        if (has80Charging && soundEnabled) {
          if (now - lastTingTime >= 10000) {
            lastTingTime = now;
            // Run sound in separate macrotask so it never delays rendering
            setTimeout(playMildTing, 0);
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
              \${isAt80 ? '<div class="alert-80-badge">🔔 80% Reached — Unplug Ready</div>' : ''}
              <div class="card-top">
                <div class="device-title" title="\${d.name}">\${d.name}</div>
                <div class="device-status \${statusCls}">\${statusText}</div>
              </div>
              \${d.maxChargingWatts > 0 ? '<div class="ceiling-tag">⚡ Hardware Limit: ' + Math.round(d.maxChargingWatts) + 'W</div>' : ''}
              <div class="watts-display \${isChg ? '' : 'idle'}">\${wText}</div>
              <div class="elec-specs">\${Math.round(d.currentMA)} mA • \${d.voltageV.toFixed(2)} V</div>
              
              <div class="chart-container"><canvas id="cvs_\${d.id}"></canvas></div>

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
        consecutiveErrors++;
        // PROFESSIONAL RULE: Only show disconnect card after 3 consecutive failures (>3 seconds of real silence)
        if (consecutiveErrors >= 3) {
          const grid = document.getElementById('devices-grid');
          const badge = document.getElementById('hub-count');
          badge.innerText = 'Offline';
          badge.style.background = 'rgba(239,100,100,0.15)';
          badge.style.color = '#EF6464';

          grid.innerHTML = `
            <div class="disconnect-card">
              <div style="font-size: 38px; margin-bottom: 10px;">🛑</div>
              <div style="font-size: 20px; font-weight: 800; color: #EF6464; margin-bottom: 6px;">Broadcast Stopped</div>
              <div style="color: var(--subtext); font-size: 13px;">Tap Start on your phone to resume streaming.</div>
            </div>
          `;
        }
      }
    }

    // Steady, stable 500ms heartbeat
    setInterval(pollHub, 500);
    pollHub();
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Monitor', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // Segmented Mode Switcher
              if (!isRunning)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161D23),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => isHostMode = true);
                            _stopDiscovery();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isHostMode ? const Color(0xFF22BFA2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                'Central Hub',
                                style: TextStyle(
                                  color: isHostMode ? Colors.black : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => isHostMode = false);
                            _startAutoDiscovery();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !isHostMode ? const Color(0xFF22BFA2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                'Join as Probe',
                                style: TextStyle(
                                  color: !isHostMode ? Colors.black : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // PROBE MODE: Clean Auto-Discovery Radar Card
              if (!isHostMode && !isRunning) ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: discoveredHubIp != null
                        ? const Color(0xFF2ECC91).withOpacity(0.08)
                        : const Color(0xFF161D23),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: discoveredHubIp != null
                          ? const Color(0xFF2ECC91).withOpacity(0.4)
                          : Colors.white10,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (discoveredHubIp != null
                                  ? const Color(0xFF2ECC91)
                                  : const Color(0xFF22BFA2))
                              .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: isSearchingForHub
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Color(0xFF22BFA2),
                                ),
                              )
                            : Icon(
                                discoveredHubIp != null
                                    ? Icons.check_circle_rounded
                                    : Icons.wifi_tethering,
                                color: discoveredHubIp != null
                                    ? const Color(0xFF2ECC91)
                                    : const Color(0xFF22BFA2),
                                size: 22,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              discoveredHubIp != null
                                  ? 'Hub Auto-Detected'
                                  : isSearchingForHub
                                      ? 'Scanning Wi-Fi...'
                                      : 'No Hub Found',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: discoveredHubIp != null
                                    ? const Color(0xFF2ECC91)
                                    : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              discoveredHubIp != null
                                  ? '$discoveredHubName ($discoveredHubIp)'
                                  : 'Start Central Hub on Phone 1 first.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFA7B0B9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isSearchingForHub && discoveredHubIp == null)
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Color(0xFF3DDDB5), size: 20),
                          tooltip: 'Scan Again',
                          onPressed: _startAutoDiscovery,
                        ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFA7B0B9),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () {
                      setState(() => showManualIpInput = !showManualIpInput);
                    },
                    child: Text(showManualIpInput ? 'Hide Manual IP' : 'Enter IP manually'),
                  ),
                ),
                if (showManualIpInput)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: hubIpController,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Manual Hub IP',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
              ],

              // MAIN SETUP CARD
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C252C),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isRunning ? const Color(0xFF22BFA2) : Colors.white10,
                  ),
                ),
                child: Column(
                  children: [
                    if (!isRunning) ...[
                      TextField(
                        controller: nicknameController,
                        decoration: InputDecoration(
                          labelText: 'Device Nickname',
                          hintText: deviceName,
                          prefixIcon: const Icon(Icons.phone_android, size: 20),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '80% Chime Alert',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Chimes in browser every 10s at 80%+',
                          style: TextStyle(fontSize: 12, color: Color(0xFFA7B0B9)),
                        ),
                        value: enable80AlertSound,
                        activeColor: const Color(0xFF22BFA2),
                        onChanged: (val) {
                          setState(() => enable80AlertSound = val);
                        },
                      ),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2ECC91),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isHostMode ? 'Hub Online' : 'Streaming Active',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF2ECC91),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101419),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF22BFA2).withOpacity(0.5)),
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
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF22BFA2),
                            side: const BorderSide(color: Color(0xFF22BFA2)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy Dashboard URL'),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: Icon(isHostMode ? Icons.play_arrow : Icons.link),
                  label: Text(
                    isHostMode
                        ? 'Start Central Hub'
                        : (discoveredHubIp != null ? 'Auto-Connect' : 'Connect to Hub'),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.stop),
                  label: const Text(
                    'Stop Session',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  onPressed: _stopSession,
                ),

              const SizedBox(height: 24),

              const Center(
                child: Text(
                  '💡 Pro-Tip: Lock your screen after connecting to unlock full 44W+ charging.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFFA7B0B9)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}