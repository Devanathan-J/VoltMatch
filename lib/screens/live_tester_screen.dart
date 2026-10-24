import 'dart:async';
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

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchHardwareStats());
    _fetchHardwareStats();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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

          if (!charging) {
            currentMA = 0.0;
          } else {
            currentMA = cMA;
          }
        });
      }
    } catch (_) {}
  }

  Color _getTempColor() {
    if (tempC < 36.0) return const Color(0xFF2ECC91); // Cool / Optimal
    if (tempC < 41.0) return const Color(0xFFF5B544); // Warm
    return const Color(0xFFEF6464); // Thermal Throttling
  }

  @override
  Widget build(BuildContext context) {
    final liveWatts = (voltageV * (currentMA / 1000.0));

    return Scaffold(
      appBar: AppBar(title: const Text('Live Meter & Cable Tester')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 1. Live Speed Gauge Card
              Container(
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
                    if (maxWatts > 0 && isCharging) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3DDDB5).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF3DDDB5).withOpacity(0.3)),
                        ),
                        child: Text(
                          '⚡ Charger Negotiated Ceiling: ${maxWatts.toStringAsFixed(0)}W',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF3DDDB5),
                          ),
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
                      isCharging ? '${liveWatts.toStringAsFixed(1)} W' : 'Not Charging',
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isCharging
                          ? '${currentMA.toStringAsFixed(0)} mA  •  ${voltageV.toStringAsFixed(2)} V'
                          : 'Plug in a charger to start measuring',
                      style: const TextStyle(color: Color(0xFFA7B0B9), fontSize: 15),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 2. Hardware Telemetry Bar (Temperature & Data Wire)
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
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: _getTempColor(),
                                ),
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

              // 3. Contextual Notice
              if (isCharging && liveWatts > 0 && liveWatts < 15) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5B544).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF5B544).withOpacity(0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFFF5B544), size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Showing 7W - 13W or Lower? Normal for screen-on or battery above 80%. Read below!',
                          style: TextStyle(
                            color: Color(0xFFF5B544),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 4. In-App Troubleshooting Guide
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF161D23),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: ExpansionTile(
                  initiallyExpanded: false,
                  shape: const Border(),
                  leading: const Icon(Icons.help_outline, color: Color(0xFF22BFA2)),
                  title: const Text(
                    'Why is Wattage lower than advertised?',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          _buildPoint(Icons.stay_current_portrait, '1. Screen-On Thermal Brake',
                              'Phones cut speed to ~7W-10W while the screen is on. Full speed occurs only when the screen is locked and OFF.'),
                          const Divider(color: Colors.white10, height: 20),
                          _buildPoint(Icons.battery_charging_full, '2. The 70%-80% Battery Rule',
                              'Fast charging only runs full blast below 60%. Above 80%, power trickles down to protect battery life.'),
                          const Divider(color: Colors.white10, height: 20),
                          _buildPoint(Icons.thermostat, '3. Battery Temperature',
                              'If your battery warms above 38°C, the phone automatically dials back charging power to cool itself.'),
                          const Divider(color: Colors.white10, height: 20),
                          _buildPoint(Icons.cable, '4. Cable Rating',
                              'Standard 2A cables bottleneck fast chargers down to 10W-15W. High-power charging requires a 4A/5A cable.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPoint(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF3DDDB5)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(color: Color(0xFFA7B0B9), fontSize: 12, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }
}