import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RemoteMonitorScreen extends StatefulWidget {
  const RemoteMonitorScreen({super.key});

  @override
  State<RemoteMonitorScreen> createState() => _RemoteMonitorScreenState();
}

class _RemoteMonitorScreenState extends State<RemoteMonitorScreen> {
  static const platform = MethodChannel('com.voltmatch/hardware');

  late bool isHostMode;

  bool enable80AlertSound = true;
  bool isRunning = false;
  bool showManualIpInput = false;

  String broadcastUrl = '';
  String cachedLocalIp = '127.0.0.1';
  final TextEditingController hubIpController = TextEditingController();
  final TextEditingController nicknameController = TextEditingController();

  // Auto-Discovery & Continuous Radar
  bool isSearchingForHub = false;
  String? discoveredHubName;
  String? discoveredHubIp;
  final List<Map<String, dynamic>> discoveredHubs = [];
  String? selectedHubIp;
  RawDatagramSocket? _udpBeaconSocket;
  RawDatagramSocket? _udpListenSocket;
  Timer? _beaconTimer;
  Timer? _realtimeRadarTimer;

  HttpServer? _server;
  Timer? _fastTimer;
  Timer? _alertWatchdogTimer;
  HttpClient? _probeClient;

  final Map<String, Map<String, dynamic>> _connectedDevices = {};
  final Map<String, List<double>> _deviceHistories = {};
  final Map<String, bool> _mutedDevices = {};

  final Set<String> _notified80Devices = {};
  DateTime _lastSoundTime = DateTime.fromMillisecondsSinceEpoch(0);

  final List<String> _csvLog = ['Timestamp,Device,Watts,Current_mA,Voltage_V,Battery_Pct,Temp_C,Is_Charging'];

  String deviceName = Platform.isWindows ? 'Windows Desktop Host' : 'Android Device';
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
    isHostMode = Platform.isWindows;

    if (Platform.isAndroid) {
      platform.invokeMethod<bool>('isProbeServiceRunning').then((running) {
        if (running == true && mounted) {
          setState(() {
            isHostMode = false;
            isRunning = true;
            broadcastUrl = 'Streaming via Quick Tile';
          });
        }
      });
    }

    _resolveLocalIp().then((_) {
      if (!isHostMode && !isRunning) {
        _startRealtimeAutoDiscovery();
      }
    });
  }

  @override
  void dispose() {
    _stopSession();
    _stopDiscovery();
    _realtimeRadarTimer?.cancel();
    hubIpController.dispose();
    nicknameController.dispose();
    super.dispose();
  }

  Future<void> _resolveLocalIp() async {
    try {
      final candidates = <MapEntry<String, int>>[];
      for (final iface in await NetworkInterface.list()) {
        final name = iface.name.toLowerCase();
        if (_isVirtualInterface(name)) continue;
        for (final addr in iface.addresses) {
          if (addr.type != InternetAddressType.IPv4 || addr.isLoopback) continue;
          final ip = addr.address;
          if (ip == '0.0.0.0' || ip.startsWith('169.254.')) continue;

          int score = 0;
          if (name.contains('wi-fi') || name.contains('wifi') || name.contains('wlan')) {
            score += 100;
          } else if (name.contains('eth') || name.contains('lan')) {
            score += 90;
          } else {
            score += 10;
          }
          candidates.add(MapEntry(ip, score));
        }
      }

      if (candidates.isNotEmpty) {
        candidates.sort((a, b) => b.value.compareTo(a.value));
        if (mounted) setState(() => cachedLocalIp = candidates.first.key);
        return;
      }
    } catch (_) {}

    try {
      for (var iface in await NetworkInterface.list()) {
        for (var addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            if (mounted) setState(() => cachedLocalIp = addr.address);
            return;
          }
        }
      }
    } catch (_) {}
  }

  bool _isVirtualInterface(String name) {
    const virtualKeywords = [
      'virtual', 'vethernet', 'vmware', 'virtualbox', 'hyper-v', 'hyperv',
      'wsl', 'docker', 'tap', 'tun', 'vpn', 'pseudo', 'loopback', 'npcap', 'bluetooth',
    ];
    for (final k in virtualKeywords) {
      if (name.contains(k)) return true;
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────
  // AUTO-DISCOVERY RADAR
  // ─────────────────────────────────────────────────────────────

  void _startRealtimeAutoDiscovery() {
    if (isRunning) return;
    setState(() => isSearchingForHub = true);

    _startUdpListener();
    _scanSubnetOnce();

    _realtimeRadarTimer?.cancel();
    _realtimeRadarTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!isRunning && !isHostMode && mounted) {
        _verifyAndPruneHubs();
      }
    });
  }

  Future<void> _startUdpListener() async {
    try {
      _udpListenSocket?.close();
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
              if (data['type'] == 'VOLTMATCH_HUB') {
                final sourceIp = datagram.address.address;
                final hubIp = sourceIp.isNotEmpty ? sourceIp : (data['ip']?.toString() ?? '');
                if (hubIp.isNotEmpty) {
                  _onHubPingReceived(hubIp, data['name'] ?? 'VoltMatch Hub');
                }
              }
            } catch (_) {}
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _scanSubnetOnce() async {
    if (cachedLocalIp == '127.0.0.1' || !mounted || isRunning) return;
    final parts = cachedLocalIp.split('.');
    if (parts.length != 4) return;
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 250);

    for (int i = 1; i <= 254; i += 30) {
      if (!mounted || isRunning) break;
      final futures = <Future>[];
      for (int j = i; j < i + 30 && j <= 254; j++) {
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
                _onHubPingReceived(target, data['name'] ?? 'VoltMatch Hub');
              }
            }
          } catch (_) {}
        }());
      }
      await Future.wait(futures);
    }
    client.close(force: true);

    if (mounted && !isRunning) {
      setState(() => isSearchingForHub = false);
    }
  }

  void _onHubPingReceived(String ip, String name) {
    if (!mounted || isRunning) return;
    final index = discoveredHubs.indexWhere((h) => h['ip'] == ip);

    setState(() {
      if (index >= 0) {
        discoveredHubs[index]['lastSeen'] = DateTime.now().millisecondsSinceEpoch;
        discoveredHubs[index]['name'] = name;
      } else {
        discoveredHubs.add({'ip': ip, 'name': name, 'lastSeen': DateTime.now().millisecondsSinceEpoch});
      }

      if (selectedHubIp == null || !discoveredHubs.any((h) => h['ip'] == selectedHubIp)) {
        selectedHubIp = ip;
        discoveredHubIp = ip;
        discoveredHubName = name;
        hubIpController.text = ip;
      }
      isSearchingForHub = false;
    });
  }

  Future<void> _verifyAndPruneHubs() async {
    if (discoveredHubs.isEmpty || isRunning || !mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      discoveredHubs.removeWhere((h) => (now - (h['lastSeen'] as int)) > 3000);

      if (discoveredHubs.isEmpty) {
        discoveredHubIp = null;
        discoveredHubName = null;
        selectedHubIp = null;
        hubIpController.clear();
        isSearchingForHub = true;
      } else if (selectedHubIp == null || !discoveredHubs.any((h) => h['ip'] == selectedHubIp)) {
        selectedHubIp = discoveredHubs.first['ip'];
        discoveredHubIp = discoveredHubs.first['ip'];
        discoveredHubName = discoveredHubs.first['name'];
        hubIpController.text = discoveredHubIp!;
      }
    });
  }

  void _stopDiscovery() {
    _beaconTimer?.cancel();
    _realtimeRadarTimer?.cancel();
    _udpBeaconSocket?.close();
    _udpListenSocket?.close();
    _udpBeaconSocket = null;
    _udpListenSocket = null;
  }

  // ─────────────────────────────────────────────────────────────
  // AUDIO & NOTIFICATION ENGINE
  // ─────────────────────────────────────────────────────────────

  void _playAlertChime() {
    if (Platform.isWindows) {
      Process.start('powershell', [
        '-NoProfile',
        '-WindowStyle', 'Hidden',
        '-Command',
        r'''
        $soundFiles = @(
          'C:\Windows\Media\Windows Notify System Generic.wav',
          'C:\Windows\Media\Windows Background.wav',
          'C:\Windows\Media\notify.wav',
          'C:\Windows\Media\chimes.wav'
        )
        $played = $false
        foreach ($f in $soundFiles) {
          if (Test-Path $f) {
            try {
              (New-Object Media.SoundPlayer $f).PlaySync()
              $played = $true
              break
            } catch {}
          }
        }
        if (-not $played) {
          [Console]::Beep(1760, 200)
          [Console]::Beep(2637, 250)
        }
        '''
      ]);
    } else if (Platform.isAndroid) {
      platform.invokeMethod('playSystemChime');
      HapticFeedback.heavyImpact();
    }
  }

  void _showWindowsNotification(String deviceLabel, int pct) {
    if (Platform.isWindows) {
      final safeName = deviceLabel.replaceAll('"', '').replaceAll("'", '');
      Process.run('powershell', [
        '-NoProfile',
        '-WindowStyle', 'Hidden',
        '-Command',
        '''
        try {
          [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
          [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
          \$xml = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>⚡ VoltMatch: 80% Reached!</text>
      <text>$safeName is at $pct%. Unplug recommended.</text>
    </binding>
  </visual>
</toast>
"@
          \$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
          \$doc.LoadXml(\$xml)
          \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$doc)
          [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe").Show(\$toast)
        } catch {}
        '''
      ]);
    }
  }

  void _testAlertSound() {
    _playAlertChime();
    _showWindowsNotification('Test Device', 80);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔔 Testing Chime & Notification...'),
        backgroundColor: Color(0xFF22BFA2),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _runAlertWatchdog() {
    if (!enable80AlertSound) return;

    bool anyDeviceNeedsSound = false;
    final now = DateTime.now();

    for (var entry in _connectedDevices.entries) {
      final id = entry.key;
      final d = entry.value;

      if (_mutedDevices[id] == true) continue;

      final name = d['name']?.toString() ?? 'Device';
      final bat = (d['batteryPct'] as num?)?.toInt() ?? 0;
      final watts = (d['watts'] as num?)?.toDouble() ?? 0.0;
      final rawChg = d['isCharging'];
      final isPlugged = (rawChg == true || rawChg == 'true' || watts > 0.3);

      if (bat >= 80 && isPlugged) {
        anyDeviceNeedsSound = true;
        if (!_notified80Devices.contains(id)) {
          _notified80Devices.add(id);
          _showWindowsNotification(name, bat);
        }
      } else if (!isPlugged) {
        _notified80Devices.remove(id);
      }
    }

    if (anyDeviceNeedsSound) {
      final hasNeverPlayed = _lastSoundTime.millisecondsSinceEpoch == 0;
      if (hasNeverPlayed || now.difference(_lastSoundTime).inSeconds >= 10) {
        _lastSoundTime = now;
        _playAlertChime();
      }
    } else {
      _lastSoundTime = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<void> _exportCsvLog() async {
    try {
      final userProfile = Platform.environment['USERPROFILE'] ?? '.';
      final downloadsDir = Directory('$userProfile\\Downloads');
      final file = File('${downloadsDir.path}\\voltmatch_session_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(_csvLog.join('\n'));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📥 Exported log to: ${file.path}'),
            backgroundColor: const Color(0xFF22BFA2),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  // TELEMETRY SAMPLING & IMMUTABLE GRAPH HISTORY
  // ─────────────────────────────────────────────────────────────

  Future<void> _fetchSelfStats() async {
    if (Platform.isAndroid) {
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
            currentMA = charging ? cMA : 0.0;
            liveWatts = voltageV * (currentMA / 1000.0);

            if (isHostMode) {
              final effectiveName = nicknameController.text.trim().isNotEmpty
                  ? nicknameController.text.trim()
                  : deviceName;

              _recordDeviceTelemetry('self', {
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
              });
            }
          });
        }
      } catch (_) {}
    }
  }

  void _recordDeviceTelemetry(String id, Map<String, dynamic> data) {
    _connectedDevices[id] = data;

    // FIX: Generate a NEW List instance every tick so Flutter's CustomPainter always repaints!
    final previousHistory = _deviceHistories[id] ?? List.filled(25, 0.0);
    final watts = (data['watts'] as num?)?.toDouble() ?? 0.0;

    final updatedHistory = List<double>.from(previousHistory)..add(watts);
    if (updatedHistory.length > 25) {
      updatedHistory.removeAt(0);
    }
    _deviceHistories[id] = updatedHistory;

    final now = DateTime.now();
    _csvLog.add('${now.toIso8601String()},${data["name"]},${data["watts"]},${data["currentMA"]},${data["voltageV"]},${data["batteryPct"]},${data["tempC"]},${data["isCharging"]}');
    if (_csvLog.length > 3000) _csvLog.removeAt(1);
  }

  Future<void> _ensureWindowsFirewall() async {
    try {
      for (final args in [
        ['advfirewall', 'firewall', 'add', 'rule', 'name=VoltMatch Hub TCP 8080', 'dir=in', 'action=allow', 'protocol=TCP', 'localport=8080', 'profile=any', 'enable=yes'],
        ['advfirewall', 'firewall', 'add', 'rule', 'name=VoltMatch Discovery UDP 8082', 'dir=in', 'action=allow', 'protocol=UDP', 'localport=8082', 'profile=any', 'enable=yes'],
      ]) {
        await Process.run('netsh', args);
      }
    } catch (_) {}
  }

  Future<void> _startUdpBeacon() async {
    try {
      _udpBeaconSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpBeaconSocket?.broadcastEnabled = true;

      _beaconTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
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
        try {
          final parts = cachedLocalIp.split('.');
          if (parts.length == 4) {
            final bcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            _udpBeaconSocket?.send(msg, InternetAddress(bcast), 8082);
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  // START: Host
  Future<void> _startHost() async {
    _stopDiscovery();
    await _resolveLocalIp();
    if (Platform.isAndroid) {
      await platform.invokeMethod('acquireWakeLock');
    }

    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
    setState(() {
      isRunning = true;
      broadcastUrl = 'http://$cachedLocalIp:8080';
    });

    _startUdpBeacon();

    if (Platform.isWindows) {
      _ensureWindowsFirewall();
    }

    _fastTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      _fetchSelfStats();
      _pruneStaleDevices();
      if (mounted) setState(() {});
    });

    _alertWatchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _runAlertWatchdog();
    });

    _server!.listen((HttpRequest req) async {
      req.response.headers.add('Access-Control-Allow-Origin', '*');
      req.response.headers.add('Access-Control-Allow-Headers', '*');
      req.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      req.response.headers.add('Cache-Control', 'no-cache');

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
          if (mounted) setState(() => enable80AlertSound = enabled);
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
          _recordDeviceTelemetry(id, data);

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
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Hub selected or detected')),
      );
      return;
    }

    bool isHubOnline = false;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
      final req = await client.getUrl(Uri.parse('http://$targetIp:8080/api/discover'));
      final res = await req.close();
      if (res.statusCode == HttpStatus.ok) isHubOnline = true;
      client.close(force: true);
    } catch (_) {}

    if (!isHubOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Target Hub at $targetIp is offline or closed!'),
            backgroundColor: const Color(0xFFEF6464),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (Platform.isAndroid) {
      await platform.invokeMethod('acquireWakeLock');
    }
    _probeClient = HttpClient()..connectionTimeout = const Duration(seconds: 1);

    setState(() {
      isRunning = true;
      broadcastUrl = 'Streaming to $targetIp';
    });

    final selfId = 'probe_${Platform.operatingSystem}_${cachedLocalIp.replaceAll('.', '_')}';
    int consecutiveSendFailures = 0;
    bool isHandlingDisconnect = false;

    _fastTimer?.cancel();
    _fastTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (isHandlingDisconnect || !isRunning) return;

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

        consecutiveSendFailures = 0;
      } catch (_) {
        consecutiveSendFailures++;
        if (consecutiveSendFailures >= 3 && !isHandlingDisconnect) {
          isHandlingDisconnect = true;
          _fastTimer?.cancel();

          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Hub disconnected! Returning to radar scan...'),
                backgroundColor: Color(0xFFEF6464),
                duration: Duration(seconds: 2),
              ),
            );
          }
          _stopSession();
        }
      }
    });
  }

  Future<void> _stopSession() async {
    _fastTimer?.cancel();
    _alertWatchdogTimer?.cancel();
    _probeClient?.close(force: true);
    await _server?.close(force: true);

    if (Platform.isAndroid) {
      await platform.invokeMethod('stopProbeService');
      await platform.invokeMethod('releaseWakeLock');
    }

    if (mounted) {
      setState(() {
        isRunning = false;
        broadcastUrl = '';
        _connectedDevices.clear();
        _deviceHistories.clear();
        _notified80Devices.clear();
        _lastSoundTime = DateTime.fromMillisecondsSinceEpoch(0);
        liveWatts = 0.0;
        currentMA = 0.0;
        isCharging = false;
      });
    }

    if (!isHostMode) {
      _startRealtimeAutoDiscovery();
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

  void _showHubShareDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161D23),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF22BFA2), width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.hub, color: Color(0xFF22BFA2)),
            SizedBox(width: 8),
            Text('Hub Connection Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Other phones and computers on your Wi-Fi can view this dashboard live:',
              style: TextStyle(color: Color(0xFFA7B0B9), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF101419),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: SelectableText(
                broadcastUrl,
                style: const TextStyle(
                  color: Color(0xFF3DDDB5),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Port: 8080 (Dashboard) • Port: 8082 (UDP Discovery)',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22BFA2),
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy URL'),
            onPressed: () {
              _copyLink();
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // WEB DASHBOARD HTML (FIXED IN-PLACE CANVAS UPDATES)
  // ─────────────────────────────────────────────────────────────

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
      transition: border-color 0.3s ease;
    }
    .device-card.charging { border-color: rgba(34,191,162,0.45); }
    .device-card.low-bat { border-color: rgba(239,100,100,0.5); }
    .device-card.at-80 { border-color: rgba(245,181,68,0.6); }
    .card-top { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 12px; }
    .device-title { font-size: 16px; font-weight: 700; color: #fff; max-width: 70%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .device-status { font-size: 11px; font-weight: 700; padding: 4px 10px; border-radius: 12px; text-transform: uppercase; }
    .status-charging { background: rgba(46,204,145,0.15); color: #2ECC91; }
    .status-idle { background: rgba(255,255,255,0.08); color: var(--subtext); }
    .ceiling-tag { font-size: 11px; color: var(--accent-bright); font-weight: 600; margin-bottom: 2px; }
    .watts-display { font-size: 44px; font-weight: 800; color: var(--accent); letter-spacing: -1px; line-height: 1; margin: 6px 0; }
    .watts-display.idle { color: var(--subtext); }
    .elec-specs { font-size: 13px; color: var(--subtext); margin-bottom: 6px; }
    .eta-line { font-size: 12px; color: #3DDDB5; font-weight: 600; margin-bottom: 10px; }
    .chart-container {
      width: 100%;
      height: 75px;
      background: rgba(0,0,0,0.28);
      border-radius: 10px;
      overflow: hidden;
      margin-bottom: 14px;
      border: 1px solid rgba(255,255,255,0.04);
      position: relative;
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
    let consecutiveErrors = 0;
    const deviceHistories = {};

    function getAudioContext() {
      if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      if (audioCtx && audioCtx.state === 'suspended') audioCtx.resume();
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
        gain1.exponentialRampToValueAtTime(0.0001, now + 0.8);
        osc1.connect(gain1);
        gain1.connect(ctx.destination);
        osc1.start(now);
        osc1.stop(now + 0.8);

        const osc2 = ctx.createOscillator();
        const gain2 = ctx.createGain();
        osc2.type = 'sine';
        osc2.frequency.setValueAtTime(2637, now);
        gain2.gain.setValueAtTime(0.09, now);
        gain2.exponentialRampToValueAtTime(0.0001, now + 0.6);
        osc2.connect(gain2);
        gain2.connect(ctx.destination);
        osc2.start(now);
        osc2.stop(now + 0.6);
      } catch(e) {}
    }

    function calculateEta(bat, watts) {
      if (!watts || watts < 1.0) return '';
      const capWh = 19.25;
      if (bat < 80) {
        const remWh = ((80 - bat) / 100) * capWh;
        const mins = Math.round((remWh / watts) * 60);
        return mins > 0 ? '⏱️ Est. to 80%: ~' + mins + ' min' : '⏱️ Nearing 80%';
      } else if (bat < 100) {
        const remWh = ((100 - bat) / 100) * capWh;
        const mins = Math.round((remWh / Math.min(watts, 4.0)) * 60);
        return mins > 0 ? '⏱️ Est. to 100%: ~' + mins + ' min' : '⏱️ Trickle charging';
      }
      return '🔋 Battery Full';
    }

    // Modern High-Tech Oscilloscope Canvas Renderer with Glow & Gradient
    function drawSparkline(canvasId, historyData, isChg, currentWatts) {
      const cvs = document.getElementById(canvasId);
      if (!cvs) return;
      const ctx = cvs.getContext('2d');
      const w = cvs.width = cvs.offsetWidth || 300;
      const h = cvs.height = cvs.offsetHeight || 75;
      ctx.clearRect(0, 0, w, h);

      if (!historyData || historyData.length === 0) return;

      let maxVal = 5.0;
      for (let i = 0; i < historyData.length; i++) {
        if (historyData[i] > maxVal) maxVal = historyData[i];
      }
      maxVal *= 1.15; // 15% headroom

      const stepX = w / (historyData.length - 1);
      const scaleY = (h - 14) / maxVal;

      // 1. Draw glowing gradient fill under curve
      const grad = ctx.createLinearGradient(0, 0, 0, h);
      grad.addColorStop(0, isChg ? 'rgba(34,191,162,0.32)' : 'rgba(167,176,185,0.15)');
      grad.addColorStop(1, 'rgba(0,0,0,0)');

      ctx.beginPath();
      for (let i = 0; i < historyData.length; i++) {
        const x = i * stepX;
        const y = h - (historyData[i] * scaleY) - 6;
        if (i === 0) {
          ctx.moveTo(x, h);
          ctx.lineTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.lineTo(w, h);
      ctx.closePath();
      ctx.fillStyle = grad;
      ctx.fill();

      // 2. Draw crisp stroke line
      ctx.beginPath();
      for (let i = 0; i < historyData.length; i++) {
        const x = i * stepX;
        const y = h - (historyData[i] * scaleY) - 6;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.strokeStyle = isChg ? '#22BFA2' : '#A7B0B9';
      ctx.lineWidth = 2.2;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.stroke();

      // 3. Draw live pulsing beacon dot at the head
      if (isChg && currentWatts > 0.2) {
        const lastX = w - 4;
        const lastY = h - (historyData[historyData.length - 1] * scaleY) - 6;

        ctx.beginPath();
        ctx.arc(lastX, lastY, 5, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(61,221,181,0.4)';
        ctx.fill();

        ctx.beginPath();
        ctx.arc(lastX, lastY, 2.5, 0, Math.PI * 2);
        ctx.fillStyle = '#3DDDB5';
        ctx.fill();
      }
    }

    async function pollHub() {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 2000);
        const res = await fetch('/api/stats', { signal: controller.signal });
        clearTimeout(timeoutId);

        if (!res.ok) throw new Error("Offline");
        const payload = await res.json();
        const devices = payload.devices || [];

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

        const has80Charging = devices.some(d => {
          const w = d.watts || 0;
          return d.batteryPct >= 80 && (d.isCharging === true || w > 0.3);
        });

        const now = Date.now();
        if (has80Charging && soundEnabled) {
          if (now - lastTingTime >= 10000) {
            lastTingTime = now;
            setTimeout(playMildTing, 0);
          }
        } else {
          lastTingTime = 0;
        }

        // Render cards only if device count or IDs changed, otherwise update values in-place!
        const existingCards = document.querySelectorAll('.device-card');
        if (existingCards.length !== devices.length) {
          let html = '';
          devices.forEach((d) => {
            html += `
              <div class="device-card" id="card_\${d.id}">
                <div class="alert-80-badge" id="badge80_\${d.id}" style="display:none;">🔔 80% Reached — Unplug Ready</div>
                <div class="card-top">
                  <div class="device-title" id="title_\${d.id}">\${d.name}</div>
                  <div class="device-status" id="status_\${d.id}"></div>
                </div>
                <div class="ceiling-tag" id="ceiling_\${d.id}"></div>
                <div class="watts-display" id="watts_\${d.id}">0.0 W</div>
                <div class="elec-specs" id="specs_\${d.id}"></div>
                <div class="eta-line" id="eta_\${d.id}"></div>
                <div class="chart-container"><canvas id="cvs_\${d.id}"></canvas></div>
                <div class="stats-row">
                  <div class="pill">
                    <div class="pill-label">Battery Level</div>
                    <div class="pill-val" id="bat_\${d.id}">--%</div>
                  </div>
                  <div class="pill">
                    <div class="pill-label">Temperature</div>
                    <div class="pill-val" id="temp_\${d.id}">-- °C</div>
                  </div>
                </div>
              </div>
            `;
          });
          grid.innerHTML = html;
        }

        // Update live data into cards without destroying DOM elements!
        devices.forEach((d) => {
          const w = d.watts || 0;
          const isChg = (d.isCharging === true || w > 0.3);
          const isAt80 = d.batteryPct >= 80 && isChg;
          const isLow = d.batteryPct < 20;

          const card = document.getElementById('card_' + d.id);
          if (card) {
            card.className = 'device-card ' + (isAt80 ? 'at-80' : (isLow ? 'low-bat' : (isChg ? 'charging' : '')));
          }

          const b80 = document.getElementById('badge80_' + d.id);
          if (b80) b80.style.display = isAt80 ? 'block' : 'none';

          const titleEl = document.getElementById('title_' + d.id);
          if (titleEl) titleEl.innerText = d.name;

          const statusEl = document.getElementById('status_' + d.id);
          if (statusEl) {
            statusEl.className = 'device-status ' + (isChg ? 'status-charging' : 'status-idle');
            statusEl.innerText = isChg ? '⚡ Charging' : 'Unplugged';
          }

          const ceilEl = document.getElementById('ceiling_' + d.id);
          if (ceilEl) {
            ceilEl.innerText = d.maxChargingWatts > 0 ? '⚡ Limit: ' + Math.round(d.maxChargingWatts) + 'W' : '';
          }

          const wEl = document.getElementById('watts_' + d.id);
          if (wEl) {
            wEl.className = 'watts-display ' + (isChg ? '' : 'idle');
            wEl.innerText = isChg ? d.watts.toFixed(1) + ' W' : '0.0 W';
          }

          const specsEl = document.getElementById('specs_' + d.id);
          if (specsEl) {
            specsEl.innerText = Math.round(d.currentMA) + ' mA • ' + d.voltageV.toFixed(2) + ' V';
          }

          const etaEl = document.getElementById('eta_' + d.id);
          if (etaEl) {
            etaEl.innerText = isChg ? calculateEta(d.batteryPct, d.watts) : '';
          }

          const batEl = document.getElementById('bat_' + d.id);
          if (batEl) {
            batEl.innerText = d.batteryPct + '%';
            batEl.style.color = isLow ? '#EF6464' : '#FFFFFF';
          }

          const tempEl = document.getElementById('temp_' + d.id);
          if (tempEl) {
            tempEl.innerText = d.tempC.toFixed(1) + ' °C';
            tempEl.style.color = d.tempC > 40 ? '#EF6464' : (d.tempC > 36 ? '#F5B544' : '#2ECC91');
          }

          // Push into continuous graph history
          if (!deviceHistories[d.id]) {
            deviceHistories[d.id] = new Array(25).fill(0.0);
          }
          deviceHistories[d.id].push(isChg ? d.watts : 0.0);
          if (deviceHistories[d.id].length > 25) {
            deviceHistories[d.id].shift();
          }

          // Draw active glowing oscilloscope canvas!
          drawSparkline('cvs_' + d.id, deviceHistories[d.id], isChg, d.watts);
        });

      } catch(e) {
        consecutiveErrors++;
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

    setInterval(pollHub, 500);
    pollHub();
  </script>
</body>
</html>
''';
  }

  // ─────────────────────────────────────────────────────────────
  // FLUTTER UI: MOBILE & DESKTOP SWITCHER
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (isRunning && isHostMode) {
      return _buildInAppDashboard();
    }

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
              Opacity(
                opacity: isRunning ? 0.55 : 1.0,
                child: Container(
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
                          onTap: isRunning
                              ? () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please stop the active session before switching modes.'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              : () {
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
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (isRunning && isHostMode)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: Icon(Icons.lock_outline, size: 14, color: Colors.black),
                                    ),
                                  Text(
                                    'Central Hub',
                                    style: TextStyle(
                                      color: isHostMode ? Colors.black : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: isRunning
                              ? () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please stop the active session before switching modes.'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              : () {
                                  setState(() => isHostMode = false);
                                  _startRealtimeAutoDiscovery();
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !isHostMode ? const Color(0xFF22BFA2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (isRunning && !isHostMode)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: Icon(Icons.lock_outline, size: 14, color: Colors.black),
                                    ),
                                  Text(
                                    'Join as Probe',
                                    style: TextStyle(
                                      color: !isHostMode ? Colors.black : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (!isHostMode && !isRunning && discoveredHubs.length > 1) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: InkWell(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: const Color(0xFF161D23),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (ctx) => Container(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Select Central Hub',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 12),
                              ...discoveredHubs.map((h) {
                                final isSelected = h['ip'] == selectedHubIp;
                                return ListTile(
                                  tileColor: isSelected ? const Color(0xFF1C252C) : Colors.transparent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  leading: const Icon(Icons.hub, color: Color(0xFF22BFA2)),
                                  title: Text(h['name'] ?? 'Hub', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(h['ip'] ?? '', style: const TextStyle(color: Color(0xFFA7B0B9), fontSize: 12)),
                                  trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF22BFA2)) : null,
                                  onTap: () {
                                    setState(() {
                                      selectedHubIp = h['ip'];
                                      discoveredHubIp = h['ip'];
                                      discoveredHubName = h['name'];
                                      hubIpController.text = h['ip']!;
                                    });
                                    Navigator.pop(ctx);
                                  },
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161D23),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF22BFA2).withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Multiple Hubs Found — Tap to Switch:', style: TextStyle(color: Color(0xFFA7B0B9), fontSize: 11)),
                                const SizedBox(height: 2),
                                Text(
                                  '$discoveredHubName ($discoveredHubIp)',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, color: Color(0xFF22BFA2)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // PROBE MODE: Radar Card
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
                                  : 'Start Central Hub on PC or Phone 1 first.',
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
                          onPressed: _startRealtimeAutoDiscovery,
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
                          labelText: 'Device / Host Nickname',
                          hintText: deviceName,
                          prefixIcon: Icon(Platform.isWindows ? Icons.desktop_windows : Icons.devices, size: 20),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '80% Chime & Notification Alert',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Notifies once and chimes every 10s at 80%+',
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
                            isHostMode ? 'Central Hub Live' : 'Streaming Active',
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101419),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF22BFA2).withOpacity(0.5)),
                        ),
                        child: SelectableText(
                          broadcastUrl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
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
                          icon: const Icon(Icons.share, size: 16),
                          label: const Text('Share / View Hub Details'),
                          onPressed: _showHubShareDialog,
                        ),
                      ],
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              if (!isRunning)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22BFA2),
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: Icon(isHostMode ? (Platform.isWindows ? Icons.dashboard : Icons.play_arrow) : Icons.link),
                  label: Text(
                    isHostMode
                        ? (Platform.isWindows ? 'Open In-App Mission Control' : 'Start Central Hub')
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

              if (!Platform.isWindows) ...[
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    '💡 Tip: Lock your screen after connecting to continue receiving exact data.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFFA7B0B9)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // NATIVE IN-APP DASHBOARD VIEW
  // ─────────────────────────────────────────────────────────────

  Widget _buildInAppDashboard() {
    final devices = _connectedDevices.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.bolt, color: Color(0xFF22BFA2)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                Platform.isWindows ? 'VoltMatch Desktop Mission Control' : 'Hub Live Dashboard',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (!Platform.isWindows) ...[
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              color: const Color(0xFF1C252C),
              onSelected: (val) {
                if (val == 'test_sound') _testAlertSound();
                if (val == 'export_csv') _exportCsvLog();
                if (val == 'toggle_sound') {
                  setState(() => enable80AlertSound = !enable80AlertSound);
                }
                if (val == 'share_hub') _showHubShareDialog();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'test_sound',
                  child: Row(children: [Icon(Icons.volume_up, color: Color(0xFF3DDDB5), size: 18), SizedBox(width: 10), Text('Test Chime')]),
                ),
                const PopupMenuItem(
                  value: 'export_csv',
                  child: Row(children: [Icon(Icons.file_download, color: Color(0xFF3DDDB5), size: 18), SizedBox(width: 10), Text('Export CSV')]),
                ),
                PopupMenuItem(
                  value: 'toggle_sound',
                  child: Row(children: [
                    Icon(enable80AlertSound ? Icons.notifications_active : Icons.notifications_off, color: const Color(0xFF3DDDB5), size: 18),
                    const SizedBox(width: 10),
                    Text(enable80AlertSound ? 'Sound: ON' : 'Sound: OFF')
                  ]),
                ),
                const PopupMenuItem(
                  value: 'share_hub',
                  child: Row(children: [Icon(Icons.share, color: Color(0xFF22BFA2), size: 18), SizedBox(width: 10), Text('Hub Details')]),
                ),
              ],
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.volume_up, color: Color(0xFF3DDDB5)),
              tooltip: 'Test Sound & Windows Notification',
              onPressed: _testAlertSound,
            ),
            IconButton(
              icon: const Icon(Icons.file_download, color: Color(0xFF3DDDB5)),
              tooltip: 'Export CSV Log to Downloads',
              onPressed: _exportCsvLog,
            ),
            IconButton(
              icon: Icon(
                enable80AlertSound ? Icons.notifications_active : Icons.notifications_off,
                color: enable80AlertSound ? const Color(0xFF3DDDB5) : Colors.grey,
              ),
              tooltip: '80% Sound & Notification Alert',
              onPressed: () {
                setState(() => enable80AlertSound = !enable80AlertSound);
              },
            ),
            IconButton(
              icon: const Icon(Icons.share, color: Color(0xFF22BFA2)),
              tooltip: 'Share / View Hub Details',
              onPressed: _showHubShareDialog,
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFEF6464),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              icon: const Icon(Icons.stop, size: 16),
              label: const Text('Stop', style: TextStyle(fontSize: 12)),
              onPressed: _stopSession,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: const Color(0xFF161D23),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Color(0xFF2ECC91), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Hub Online at $broadcastUrl',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFA7B0B9), fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${devices.length} ${devices.length == 1 ? "Device" : "Devices"} Active',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF22BFA2)),
                ),
              ],
            ),
          ),
          Expanded(
            child: devices.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sensors, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Waiting for devices to connect...',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Open VoltMatch on your phones to stream here automatically.',
                          style: TextStyle(color: Color(0xFFA7B0B9), fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      int crossAxisCount = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);

                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: constraints.maxWidth > 600 ? 1.45 : 1.35,
                        ),
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final d = devices[index];
                          final id = d['id'] as String;
                          final history = _deviceHistories[id] ?? List.filled(25, 0.0);
                          return RepaintBoundary(
                            child: _buildNativeDeviceCard(d, history),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _calculateEta(int bat, double watts) {
    if (watts < 1.0) return '';
    const capWh = 19.25;
    if (bat < 80) {
      final remWh = ((80 - bat) / 100) * capWh;
      final mins = ((remWh / watts) * 60).round();
      return mins > 0 ? '⏱️ Est. to 80%: ~$mins min' : '⏱️ Nearing 80%';
    } else if (bat < 100) {
      final remWh = ((100 - bat) / 100) * capWh;
      final mins = ((remWh / (watts.clamp(1.0, 4.0))) * 60).round();
      return mins > 0 ? '⏱️ Est. to 100%: ~$mins min' : '⏱️ Trickle charging';
    }
    return '🔋 Battery Full';
  }

  Widget _buildNativeDeviceCard(Map<String, dynamic> d, List<double> history) {
    final double watts = (d['watts'] as num?)?.toDouble() ?? 0.0;
    final rawChg = d['isCharging'];
    final bool isChg = (rawChg == true || rawChg == 'true' || watts > 0.3);
    final int bat = (d['batteryPct'] as num?)?.toInt() ?? 0;
    final double temp = (d['tempC'] as num?)?.toDouble() ?? 0.0;
    final double maxW = (d['maxChargingWatts'] as num?)?.toDouble() ?? 0.0;
    final bool isAt80 = bat >= 80 && isChg;
    final bool isLow = bat < 20;
    final String deviceId = d['id']?.toString() ?? '';
    final bool isMuted = _mutedDevices[deviceId] == true;

    Color borderColor;
    if (isAt80) {
      borderColor = const Color(0xFFF5B544).withOpacity(0.6);
    } else if (isLow) {
      borderColor = const Color(0xFFEF6464).withOpacity(0.5);
    } else if (isChg) {
      borderColor = const Color(0xFF22BFA2).withOpacity(0.45);
    } else {
      borderColor = Colors.white10;
    }

    final tempColor = temp > 40 ? const Color(0xFFEF6464) : (temp > 36 ? const Color(0xFFF5B544) : const Color(0xFF2ECC91));
    final etaText = isChg ? _calculateEta(bat, watts) : '';

    // Calculate live charger potential utilization %
    final double utilPct = (maxW > 0) ? (watts / maxW).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF161D23),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAt80) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5B544).withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF5B544)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '🔔 80% Reached — Unplug Ready',
                    style: TextStyle(color: Color(0xFFF5B544), fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _mutedDevices[deviceId] = !isMuted;
                      });
                    },
                    child: Icon(
                      isMuted ? Icons.notifications_off : Icons.notifications_active,
                      size: 14,
                      color: const Color(0xFFF5B544),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  d['name']?.toString() ?? 'Device',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(right: 8),
                    icon: Icon(
                      isMuted ? Icons.volume_off : Icons.volume_up,
                      size: 16,
                      color: isMuted ? Colors.grey : const Color(0xFF3DDDB5),
                    ),
                    tooltip: isMuted ? 'Unmute 80% Chime for this device' : 'Mute 80% Chime for this device',
                    onPressed: () {
                      setState(() {
                        _mutedDevices[deviceId] = !isMuted;
                      });
                    },
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isChg ? const Color(0xFF2ECC91).withOpacity(0.15) : Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isChg ? '⚡ Charging' : 'Unplugged',
                      style: TextStyle(
                        color: isChg ? const Color(0xFF2ECC91) : const Color(0xFFA7B0B9),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (maxW > 0) ...[
            const SizedBox(height: 2),
            Text(
              '⚡ Limit: ${maxW.toStringAsFixed(0)}W',
              style: const TextStyle(fontSize: 11, color: Color(0xFF3DDDB5), fontWeight: FontWeight.bold),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${watts.toStringAsFixed(1)} W',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: isChg ? const Color(0xFF22BFA2) : const Color(0xFFA7B0B9),
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(d["currentMA"] as num?)?.round() ?? 0} mA • ${(d["voltageV"] as num?)?.toStringAsFixed(2) ?? "0.00"} V',
                style: const TextStyle(fontSize: 12, color: Color(0xFFA7B0B9)),
              ),
            ],
          ),

          // Live ETA or Utilization Bar
          if (etaText.isNotEmpty || maxW > 0) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (etaText.isNotEmpty)
                  Text(
                    etaText,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF3DDDB5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (maxW > 0 && isChg)
                  Text(
                    '${(utilPct * 100).round()}% capacity utilized',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: const Color(0xFFA7B0B9).withOpacity(0.8),
                    ),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 6),

          // The Live Oscilloscope Graph Container
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: Colors.black26,
                width: double.infinity,
                child: CustomPaint(
                  painter: _ModernPowerOscilloscopePainter(
                    history: history,
                    currentWatts: watts,
                    isCharging: isChg,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Icon(
                        Icons.battery_std,
                        size: 16,
                        color: isLow ? const Color(0xFFEF6464) : const Color(0xFFA7B0B9),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$bat%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isLow ? const Color(0xFFEF6464) : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Icon(Icons.thermostat, size: 16, color: tempColor),
                      const SizedBox(width: 4),
                      Text(
                        '${temp.toStringAsFixed(1)} °C',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: tempColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MODERN HIGH-TECH POWER OSCILLOSCOPE PAINTER
// ─────────────────────────────────────────────────────────────

class _ModernPowerOscilloscopePainter extends CustomPainter {
  final List<double> history;
  final double currentWatts;
  final bool isCharging;

  _ModernPowerOscilloscopePainter({
    required this.history,
    required this.currentWatts,
    required this.isCharging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty || size.width <= 0 || size.height <= 0) return;

    double maxVal = 5.0;
    for (int i = 0; i < history.length; i++) {
      if (history[i] > maxVal) maxVal = history[i];
    }
    maxVal *= 1.18; // 18% headroom

    final double stepX = size.width / (history.length - 1);
    final double scaleY = (size.height - 14) / maxVal;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < history.length; i++) {
      final x = i * stepX;
      final y = size.height - (history[i] * scaleY) - 6;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // 1. Draw glowing gradient fill under curve
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (isCharging ? const Color(0xFF22BFA2) : Colors.grey).withOpacity(0.28),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // 2. Draw crisp stroke line
    final strokePaint = Paint()
      ..color = isCharging ? const Color(0xFF22BFA2) : const Color(0xFFA7B0B9)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    // 3. Draw live pulsing beacon dot at the head (tracks live electricity!)
    if (isCharging && currentWatts > 0.2) {
      final lastX = size.width - 2;
      final lastY = size.height - (history.last * scaleY) - 6;

      // Outer glow
      canvas.drawCircle(
        Offset(lastX, lastY),
        5.0,
        Paint()..color = const Color(0xFF3DDDB5).withOpacity(0.35),
      );
      // Center beacon
      canvas.drawCircle(
        Offset(lastX, lastY),
        2.5,
        Paint()..color = const Color(0xFF3DDDB5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ModernPowerOscilloscopePainter oldDelegate) {
    return true; // Always repaint with live telemetry snapshots
  }
}