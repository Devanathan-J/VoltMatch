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
  bool isCharging = false;
  bool hasDataConnection = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _fetchHardwareStats();
    });
    _fetchHardwareStats();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchHardwareStats() async {
    try {
      final Map<dynamic, dynamic> result =
          await platform.invokeMethod('getLivePowerStats');
      if (mounted) {
        setState(() {
          currentMA = (result['currentMA'] as num).toDouble();
          voltageV = (result['voltageV'] as num).toDouble();
          isCharging = result['isCharging'] as bool;
          hasDataConnection = result['hasDataConnection'] as bool;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final liveWatts = (voltageV * (currentMA / 1000.0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Meter & Cable Tester'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Main Speed Gauge Card
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

              const SizedBox(height: 16),

              // FLASH7W: Smart Contextual Notice (shows if charging between 5W and 14W)
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
                          'Showing ~7W - 13W? This is normal if your screen is ON or battery is over 80%. Read the guide below!',
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

              // Data Wire Inspection Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF161D23),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.usb, color: Color(0xFF3DDDB5), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Cable Data Wire Check',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          hasDataConnection ? Icons.check_circle : Icons.help_outline,
                          color: hasDataConnection ? const Color(0xFF2ECC91) : Colors.orangeAccent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hasDataConnection
                                ? 'Data Wires Active (Connected to PC/Host)'
                                : isCharging
                                    ? 'Plugged into Wall Charger (or Charge-Only wire)'
                                    : 'Connect cable to PC/Laptop to test data lines',
                            style: const TextStyle(fontSize: 13, color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // FLASH7W: 4-Point Educational Guide & Troubleshooter
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF161D23),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  shape: const Border(),
                  leading: const Icon(Icons.help_outline, color: Color(0xFF22BFA2)),
                  title: const Text(
                    'Why is my Wattage lower than advertised?',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          _buildExplainerPoint(
                            icon: Icons.stay_current_portrait,
                            title: '1. The Screen-On Thermal Brake',
                            description:
                                'To prevent dangerous heat, almost all phones cut charging speed down to ~7W – 10W the moment the screen is turned ON. Full 44W+ charging only occurs when the screen is locked and OFF.',
                          ),
                          const Divider(color: Colors.white10, height: 24),
                          _buildExplainerPoint(
                            icon: Icons.battery_charging_full,
                            title: '2. The 70%-80% Battery Saturation Rule',
                            description:
                                'Fast charging only runs at full blast when your battery is low (0% to 50%). Once your battery reaches 80%+, the phone intentionally trickles power (~10W to 13W) to prevent overheating and protect battery health.',
                          ),
                          const Divider(color: Colors.white10, height: 24),
                          _buildExplainerPoint(
                            icon: Icons.text_fields,
                            title: '3. "FlashCharge" vs "Fast Charging"',
                            description:
                                'Check your lock screen text when you plug in:\n• If it says "FlashCharge" / "SuperVOOC", you are on the 44W+ circuit.\n• If it only says "Fast charging", it is running at standard 15W/18W speed.',
                          ),
                          const Divider(color: Colors.white10, height: 24),
                          _buildExplainerPoint(
                            icon: Icons.cable,
                            title: '4. Cable Capability',
                            description:
                                'High-speed 44W+ charging requires a specialized thick cable rated for 4A. A normal 2A cable forces the phone to throttle down to safe 10W-15W speeds.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExplainerPoint({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF3DDDB5)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFFA7B0B9),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}