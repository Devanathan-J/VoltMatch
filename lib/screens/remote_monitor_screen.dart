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

  bool isBroadcasting = false;
  String broadcastUrl = '';
  HttpServer? _server;
  Timer? _metricsTimer;

  double currentMA = 0.0;
  double voltageV = 0.0;
  double liveWatts = 0.0;
  int batteryPct = 0;
  bool isCharging = false;

  @override
  void dispose() {
    _stopBroadcast();
    super.dispose();
  }

  Future<String> _getLocalIp() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  Future<void> _fetchStats() async {
    try {
      final Map<dynamic, dynamic> res =
          await platform.invokeMethod('getLivePowerStats');
      if (mounted) {
        final charging = res['isCharging'] as bool;
        final cMA = (res['currentMA'] as num).toDouble();
        final vV = (res['voltageV'] as num).toDouble();

        setState(() {
          isCharging = charging;
          voltageV = vV;
          batteryPct = res['batteryPct'] as int;

          // FIX: If unplugged, zero out discharge current so it doesn't show 0.2W - 1.1W
          if (!charging) {
            currentMA = 0.0;
            liveWatts = 0.0;
          } else {
            currentMA = cMA;
            liveWatts = voltageV * (currentMA / 1000.0);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _startBroadcast() async {
    final ip = await _getLocalIp();
    await platform.invokeMethod('acquireWakeLock');

    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
    setState(() {
      isBroadcasting = true;
      broadcastUrl = 'http://$ip:8080';
    });

    _metricsTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _fetchStats());

    _server!.listen((HttpRequest req) {
      req.response.headers.add('Access-Control-Allow-Origin', '*');

      if (req.uri.path == '/api/stats') {
        req.response
          ..headers.contentType = ContentType.json
          ..write(json.encode({
            'watts': liveWatts,
            'currentMA': currentMA,
            'voltageV': voltageV,
            'batteryPct': batteryPct,
            'isCharging': isCharging,
          }))
          ..close();
      } else {
        req.response
          ..headers.contentType = ContentType.html
          ..write(_generateHtmlDashboard())
          ..close();
      }
    });
  }

  Future<void> _stopBroadcast() async {
    _metricsTimer?.cancel();
    await _server?.close(force: true);
    await platform.invokeMethod('releaseWakeLock');
    if (mounted) {
      setState(() {
        isBroadcasting = false;
        broadcastUrl = '';
        // FIX: Reset live numbers when broadcast stops
        liveWatts = 0.0;
        currentMA = 0.0;
        voltageV = 0.0;
        isCharging = false;
      });
    }
  }

  void _copyLink() {
    if (broadcastUrl.isEmpty) return;
    Clipboard.setData(ClipboardData(text: broadcastUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied link: $broadcastUrl'),
        backgroundColor: const Color(0xFF22BFA2),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.black,
          onPressed: () {},
        ),
      ),
    );
  }

  String _generateHtmlDashboard() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>VoltMatch Remote Monitor</title>
  <style>
    body { background: #101419; color: #fff; font-family: sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; text-align: center; }
    .card { background: #1C252C; padding: 32px; border-radius: 20px; border: 2px solid #22BFA2; width: 90%; max-width: 400px; box-shadow: 0 8px 30px rgba(0,0,0,0.5); transition: all 0.3s ease; }
    .watts { font-size: 54px; font-weight: bold; color: #22BFA2; margin: 16px 0; }
    .stats { color: #A7B0B9; font-size: 16px; line-height: 1.6; }
    .badge { background: rgba(34,191,162,0.15); color: #22BFA2; padding: 6px 14px; border-radius: 20px; font-weight: bold; font-size: 13px; display: inline-block; margin-bottom: 8px; }
  </style>
</head>
<body>
  <div class="card" id="card">
    <div class="badge" id="badge">Connecting...</div>
    <div class="watts" id="w">-- W</div>
    <div class="stats" id="info">Waiting for probe...</div>
  </div>
  <script>
    async function update() {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 2000);
        const res = await fetch('/api/stats', { signal: controller.signal });
        clearTimeout(timeoutId);

        if (!res.ok) throw new Error();
        const data = await res.json();
        
        // FIX: Handle Not Charging cleanly (0.0 W)
        if (!data.isCharging) {
          document.getElementById('badge').innerText = 'Unplugged / Idle';
          document.getElementById('badge').style.color = '#A7B0B9';
          document.getElementById('badge').style.background = 'rgba(255,255,255,0.1)';
          document.getElementById('w').innerText = '0.0 W';
          document.getElementById('w').style.color = '#A7B0B9';
          document.getElementById('info').innerHTML =
            'Battery: <b>' + data.batteryPct + '%</b> • <span style="color:#EF6464">Not Charging</span>';
        } else {
          document.getElementById('badge').innerText = 'Screen-OFF Remote Probe';
          document.getElementById('badge').style.color = '#22BFA2';
          document.getElementById('badge').style.background = 'rgba(34,191,162,0.15)';
          document.getElementById('w').innerText = data.watts.toFixed(1) + ' W';
          document.getElementById('w').style.color = '#22BFA2';
          document.getElementById('info').innerHTML = 
            '<b>' + Math.round(data.currentMA) + ' mA</b> • ' + data.voltageV.toFixed(2) + ' V<br>' +
            'Battery: <b>' + data.batteryPct + '%</b> • <span style="color:#2ECC91">⚡ Charging</span>';
        }
      } catch(e) {
        // FIX: When broadcast is stopped, immediately show disconnected!
        document.getElementById('badge').innerText = 'Disconnected';
        document.getElementById('badge').style.color = '#EF6464';
        document.getElementById('badge').style.background = 'rgba(239,100,100,0.15)';
        document.getElementById('w').innerText = '-- W';
        document.getElementById('w').style.color = '#A7B0B9';
        document.getElementById('info').innerHTML = 
          '<span style="color:#EF6464; font-weight:bold;">Broadcast Stopped</span><br><span style="font-size:13px;">Tap Start on your phone to resume</span>';
      }
    }
    setInterval(update, 1000);
    update();
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remote Screen-Off Monitor')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Broadcaster Status Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C252C),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isBroadcasting
                        ? const Color(0xFF22BFA2)
                        : Colors.white12,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      isBroadcasting
                          ? Icons.wifi_tethering
                          : Icons.wifi_tethering_off,
                      size: 48,
                      color: isBroadcasting
                          ? const Color(0xFF22BFA2)
                          : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isBroadcasting
                          ? 'Broadcaster Active'
                          : 'Broadcaster Stopped',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isBroadcasting
                          ? 'Now you can TURN OFF THIS SCREEN. Watch the live numbers on your other phone!'
                          : 'Turn this phone into a remote probe to unlock full charging speed with the screen off.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFFA7B0B9), fontSize: 13),
                    ),
                    if (isBroadcasting) ...[
                      const SizedBox(height: 18),
                      // URL Display Box
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101419),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF22BFA2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: SelectableText(
                                broadcastUrl,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF3DDDB5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Share / Copy Link Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF22BFA2).withOpacity(0.15),
                          foregroundColor: const Color(0xFF22BFA2),
                          side: const BorderSide(color: Color(0xFF22BFA2)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Copy / Share Link'),
                        onPressed: _copyLink,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              if (!isBroadcasting)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22BFA2),
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Screen-Off Broadcaster',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _startBroadcast,
                )
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF6464),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Broadcaster',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _stopBroadcast,
                ),

              const SizedBox(height: 32),

              // Instructions Card
              Container(
                padding: const EdgeInsets.all(20),
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
                        Icon(Icons.directions_run,
                            color: Color(0xFF3DDDB5), size: 20),
                        SizedBox(width: 8),
                        Text('How to run this test:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                        '1. Connect both phones to the same Wi-Fi (or turn on Hotspot on one and connect the other).',
                        style: TextStyle(
                            color: Color(0xFFA7B0B9),
                            fontSize: 13,
                            height: 1.4)),
                    SizedBox(height: 6),
                    Text('2. Tap "Start Screen-Off Broadcaster" above.',
                        style: TextStyle(
                            color: Color(0xFFA7B0B9),
                            fontSize: 13,
                            height: 1.4)),
                    SizedBox(height: 6),
                    Text(
                        '3. Tap "Copy / Share Link" to send it or open it in Chrome on your other phone.',
                        style: TextStyle(
                            color: Color(0xFFA7B0B9),
                            fontSize: 13,
                            height: 1.4)),
                    SizedBox(height: 6),
                    Text(
                        '4. Plug in your charger, then TURN OFF this screen with the power button!',
                        style: TextStyle(
                            color: Color(0xFF3DDDB5),
                            fontSize: 13,
                            height: 1.4,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 6),
                    Text(
                        '5. Watch the numbers update live on your other phone without thermal throttling!',
                        style: TextStyle(
                            color: Color(0xFFA7B0B9),
                            fontSize: 13,
                            height: 1.4)),
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