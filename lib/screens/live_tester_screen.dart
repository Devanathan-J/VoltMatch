import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LiveTesterScreen extends StatefulWidget {
  const LiveTesterScreen({super.key});

  @override
  State<LiveTesterScreen> createState() => _LiveTesterScreenState();
}

class _LiveTesterScreenState extends State<LiveTesterScreen> {
  static const platform = MethodChannel('com.voltmatch/hardware');
  Timer? _timer;

  double currentMA = 0.0;
  double voltageV = 0.0;
  double tempC = 0.0;
  double maxWatts = 0.0;
  bool isCharging = false;
  bool hasDataConnection = false;

  bool isWindowsDesktop = false;
  bool isLaptop = true;
  int windowsBatteryPct = 100;
  double windowsWatts = 0.0;
  bool _isPollingWindows = false;

  @override
  void initState() {
    super.initState();
    isWindowsDesktop = Platform.isWindows;

    if (isWindowsDesktop) {
      _fetchWindowsPowerStats();
      // Increased from 3s to 5s to eliminate laptop fan spin and CPU spikes on Windows!
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchWindowsPowerStats());
    } else {
      _fetchHardwareStats();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchHardwareStats());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchWindowsPowerStats() async {
    if (_isPollingWindows) return;
    _isPollingWindows = true;

    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-WindowStyle', 'Hidden',
        '-Command',
        r'''
        $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue;
        if ($b) {
          $s = Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue;
          $chg = ($b.BatteryStatus -eq 2) -or ($b.BatteryStatus -eq 6) -or ($b.BatteryStatus -eq 7) -or ($s.Charging -eq $true);
          $v = if ($s.Voltage) { $s.Voltage / 1000.0 } else { if ($b.DesignVoltage) { $b.DesignVoltage / 1000.0 } else { 11.4 } };
          $rate = if ($s.ChargeRate -gt 0) { $s.ChargeRate / 1000.0 } else { if ($s.DischargeRate -gt 0) { $s.DischargeRate / 1000.0 } else { 45.0 } };
          Write-Output "$($b.EstimatedChargeRemaining)|$chg|$v|$rate|LAPTOP"
        } else {
          Write-Output "DESKTOP_PC"
        }
        '''
      ]);

      final out = res.stdout.toString().trim();
      if (mounted) {
        if (out.contains('DESKTOP_PC')) {
          setState(() {
            isLaptop = false;
            isCharging = true;
            voltageV = 12.0;
            windowsWatts = 120.0;
          });
        } else if (out.contains('|')) {
          final parts = out.split('|');
          final bat = int.tryParse(parts[0]) ?? 100;
          final chg = parts[1].toLowerCase() == 'true';
          final v = double.tryParse(parts[2]) ?? 11.4;
          final w = double.tryParse(parts[3]) ?? 45.0;

          setState(() {
            isLaptop = true;
            windowsBatteryPct = bat;
            isCharging = chg;
            voltageV = v;
            windowsWatts = chg ? w : 0.0;
            currentMA = (w / v) * 1000.0;
          });
        }
      }
    } catch (_) {} finally {
      _isPollingWindows = false;
    }
  }

  Future<void> _fetchHardwareStats() async {
    try {
      final Map<dynamic, dynamic> res = await platform.invokeMethod('getLivePowerStats');
      if (mounted) {
        final charging = res['isCharging'] as bool;
        final cMA = (res['currentMA'] as num).toDouble();
        final vV = (res['voltageV'] as num).toDouble();

        setState(() {
          isCharging = charging;
          voltageV = vV;
          tempC = (res['tempC'] as num).toDouble();
          maxWatts = (res['maxChargingWatts'] as num).toDouble();
          hasDataConnection = res['hasDataConnection'] as bool;
          currentMA = charging ? cMA : 0.0;
        });
      }
    } catch (_) {}
  }

  Color _getTempColor() {
    if (tempC < 36.0) return const Color(0xFF2ECC91);
    if (tempC < 41.0) return const Color(0xFFF5B544);
    return const Color(0xFFEF6464);
  }

  @override
  Widget build(BuildContext context) {
    final liveWatts = isWindowsDesktop
        ? windowsWatts
        : (voltageV * (currentMA / 1000.0));

    return Scaffold(
      appBar: AppBar(
        title: Text(isWindowsDesktop ? 'PC Power Monitor' : 'Live Meter & Cable Tester'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              RepaintBoundary(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C252C),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isCharging ? const Color(0xFF22BFA2) : Colors.white10,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      if (isWindowsDesktop && !isLaptop) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3DDDB5).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF3DDDB5).withOpacity(0.3)),
                          ),
                          child: const Text(
                            '⚡ Desktop Tower (Direct AC Wall Power)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF3DDDB5)),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ] else if (maxWatts > 0 && isCharging) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3DDDB5).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF3DDDB5).withOpacity(0.3)),
                          ),
                          child: Text(
                            '⚡ Charger Negotiated Ceiling: ${maxWatts.toStringAsFixed(0)}W',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF3DDDB5)),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      Icon(
                        isCharging ? Icons.bolt : Icons.power_off,
                        size: 46,
                        color: isCharging ? const Color(0xFF22BFA2) : Colors.grey,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isCharging
                            ? (isWindowsDesktop && !isLaptop ? 'AC Active' : '${liveWatts.toStringAsFixed(1)} W')
                            : 'On Battery Power',
                        style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isCharging
                            ? (isWindowsDesktop && !isLaptop
                                ? 'Desktop PC plugged directly into wall outlet'
                                : '${currentMA.toStringAsFixed(0)} mA  •  ${voltageV.toStringAsFixed(2)} V')
                            : 'Unplugged from charger',
                        style: const TextStyle(color: Color(0xFFA7B0B9), fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              if (!isWindowsDesktop) ...[
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161D23),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.thermostat, color: _getTempColor(), size: 22),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Battery Temp', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                Text(
                                  '${tempC.toStringAsFixed(1)} °C',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _getTempColor()),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161D23),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              hasDataConnection ? Icons.usb : Icons.usb_off,
                              color: hasDataConnection ? const Color(0xFF2ECC91) : Colors.orangeAccent,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Data Lines', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  Text(
                                    hasDataConnection ? 'Verified' : 'Wall/No PC',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: hasDataConnection ? const Color(0xFF2ECC91) : Colors.orangeAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ] else if (isLaptop) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161D23),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.laptop_chromebook, color: Color(0xFF22BFA2), size: 28),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Laptop Battery Status', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(
                            '$windowsBatteryPct% • ${isCharging ? "Charging via AC" : "Discharging on Battery"}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}