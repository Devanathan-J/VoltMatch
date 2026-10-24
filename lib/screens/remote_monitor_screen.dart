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
  double tempC = 0.0;
  double maxWatts = 0.0;
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
      final Map<dynamic, dynamic> res = await platform.invokeMethod('getLivePowerStats');
      if (mounted) {
        final charging = res['isCharging'] as bool;
        final cMA = (res['currentMA'] as num).toDouble();
        final vV = (res['voltageV'] as num).toDouble();

        setState(() {
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

    _metricsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchStats());

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
            'tempC': tempC,
            'maxChargingWatts': maxWatts,
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
        liveWatts = 0.0;
        currentMA = 0.0;
        voltageV = 0.0;
        tempC = 0.0;
        maxWatts = 0.0;
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
      ),
    );
  }

  String _generateHtmlDashboard() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>VoltMatch Remote Telemetry</title>
  <style>
    body { background: #101419; color: #fff; font-family: -apple-system, BlinkMacSystemFont, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; padding: 16px; box-sizing: border-box; }
    .card { background: #1C252C; padding: 24px; border-radius: 24px; border: 2px solid #22BFA2; width: 100%; max-width: 440px; box-shadow: 0 10px 40px rgba(0,0,0,0.6); text-align: center; }
    .badge { background: rgba(34,191,162,0.15); color: #22BFA2; padding: 6px 14px; border-radius: 20px; font-weight: bold; font-size: 13px; display: inline-block; margin-bottom: 8px; }
    .ceiling { font-size: 12px; color: #3DDDB5; font-weight: bold; margin-bottom: 4px; }
    .watts { font-size: 56px; font-weight: 800; color: #22BFA2; margin: 8px 0; letter-spacing: -1px; }
    .stats { color: #A7B0B9; font-size: 15px; line-height: 1.5; margin-bottom: 16px; }
    .alert-banner { display: none; background: rgba(245,181,68,0.2); border: 1px solid #F5B544; color: #F5B544; padding: 10px; border-radius: 12px; font-size: 13px; font-weight: bold; margin-bottom: 14px; }
    canvas { width: 100%; height: 100px; background: #101419; border-radius: 12px; border: 1px solid rgba(255,255,255,0.06); margin-top: 10px; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 14px; text-align: left; }
    .pill { background: #161D23; padding: 10px 14px; border-radius: 12px; border: 1px solid rgba(255,255,255,0.05); }
    .pill-label { font-size: 11px; color: #7F8A96; }
    .pill-value { font-size: 14px; font-weight: bold; margin-top: 2px; }
  </style>
</head>
<body>
  <div class="card">
    <div id="alert80" class="alert-banner">🔔 80% REACHED! Ready to unplug to protect battery.</div>
    <div class="badge" id="badge">Connecting...</div>
    <div class="ceiling" id="ceiling"></div>
    <div class="watts" id="w">-- W</div>
    <div class="stats" id="info">Waiting for probe data...</div>

    <!-- Live Scrolling Wattage Chart -->
    <canvas id="chart" width="400" height="120"></canvas>

    <div class="grid">
      <div class="pill">
        <div class="pill-label">Battery Level</div>
        <div class="pill-value" id="bat">--%</div>
      </div>
      <div class="pill">
        <div class="pill-label">Battery Temp</div>
        <div class="pill-value" id="temp">-- °C</div>
      </div>
    </div>
  </div>

  <script>
    let history = new Array(30).fill(0);
    let alerted80 = false;

    function play80Chime() {
      try {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.frequency.setValueAtTime(587.33, ctx.currentTime);
        osc.frequency.setValueAtTime(880, ctx.currentTime + 0.15);
        gain.gain.setValueAtTime(0.3, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.6);
        osc.start();
        osc.stop(ctx.currentTime + 0.6);
      } catch(e) {}
    }

    function drawChart() {
      const cvs = document.getElementById('chart');
      const ctx = cvs.getContext('2d');
      const w = cvs.width;
      const h = cvs.height;
      ctx.clearRect(0, 0, w, h);

      const maxVal = Math.max(20, ...history) * 1.15;
      
      // Draw grid line
      ctx.strokeStyle = 'rgba(255,255,255,0.05)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(0, h/2); ctx.lineTo(w, h/2);
      ctx.stroke();

      // Draw Watt curve
      ctx.strokeStyle = '#22BFA2';
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      for (let i = 0; i < history.length; i++) {
        const x = (i / (history.length - 1)) * w;
        const y = h - ((history[i] / maxVal) * (h - 12)) - 6;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.stroke();
    }

    async function update() {
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 2000);
        const res = await fetch('/api/stats', { signal: controller.signal });
        clearTimeout(timeout);

        if (!res.ok) throw new Error();
        const d = await res.json();

        history.push(d.isCharging ? d.watts : 0);
        history.shift();
        drawChart();

        // 80% Smart Alert
        if (d.batteryPct >= 80 && d.isCharging && !alerted80) {
          alerted80 = true;
          document.getElementById('alert80').style.display = 'block';
          play80Chime();
        }

        document.getElementById('bat').innerText = d.batteryPct + '%';
        const tempEl = document.getElementById('temp');
        tempEl.innerText = d.tempC.toFixed(1) + ' °C';
        tempEl.style.color = d.tempC > 40 ? '#EF6464' : (d.tempC > 36 ? '#F5B544' : '#2ECC91');

        if (d.maxChargingWatts > 0) {
          document.getElementById('ceiling').innerText = '⚡ Hardware Ceiling: ' + Math.round(d.maxChargingWatts) + 'W';
        } else {
          document.getElementById('ceiling').innerText = '';
        }

        if (!d.isCharging) {
          document.getElementById('badge').innerText = 'Unplugged / Idle';
          document.getElementById('badge').style.color = '#A7B0B9';
          document.getElementById('badge').style.background = 'rgba(255,255,255,0.1)';
          document.getElementById('w').innerText = '0.0 W';
          document.getElementById('w').style.color = '#A7B0B9';
          document.getElementById('info').innerHTML = '<span style="color:#EF6464">Not Charging</span>';
        } else {
          document.getElementById('badge').innerText = 'Screen-OFF Remote Probe';
          document.getElementById('badge').style.color = '#22BFA2';
          document.getElementById('badge').style.background = 'rgba(34,191,162,0.15)';
          document.getElementById('w').innerText = d.watts.toFixed(1) + ' W';
          document.getElementById('w').style.color = '#22BFA2';
          document.getElementById('info').innerHTML = '<b>' + Math.round(d.currentMA) + ' mA</b> • ' + d.voltageV.toFixed(2) + ' V';
        }
      } catch(e) {
        document.getElementById('badge').innerText = 'Disconnected';
        document.getElementById('badge').style.color = '#EF6464';
        document.getElementById('badge').style.background = 'rgba(239,100,100,0.15)';
        document.getElementById('w').innerText = '-- W';
        document.getElementById('w').style.color = '#A7B0B9';
        document.getElementById('info').innerHTML = '<span style="color:#EF6464; font-weight:bold;">Broadcast Stopped</span>';
      }
    }

    setInterval(update, 1000);
    drawChart();
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
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C252C),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isBroadcasting ? const Color(0xFF22BFA2) : Colors.white12,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      isBroadcasting ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                      size: 48,
                      color: isBroadcasting ? const Color(0xFF22BFA2) : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isBroadcasting ? 'Broadcaster Active' : 'Broadcaster Stopped',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isBroadcasting
                          ? 'Now you can TURN OFF THIS SCREEN. Watch the live graph on your other phone!'
                          : 'Turn this phone into a remote probe to unlock full charging speed with the screen off.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFA7B0B9), fontSize: 13),
                    ),
                    if (isBroadcasting) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22BFA2).withOpacity(0.15),
                          foregroundColor: const Color(0xFF22BFA2),
                          side: const BorderSide(color: Color(0xFF22BFA2)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
              if (!isBroadcasting)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22BFA2),
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Screen-Off Broadcaster', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _startBroadcast,
                )
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF6464),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Broadcaster', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _stopBroadcast,
                ),
            ],
          ),
        ),
      ),
    );
  }
}