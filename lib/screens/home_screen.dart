import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'selection_screen.dart';
import 'history_screen.dart';
import 'live_tester_screen.dart';
import 'remote_monitor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.voltmatch/hardware');

  bool _isNotifActive = false;
  bool _isBatActive = false;
  StateSetter? _dialogSetState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Platform.isAndroid) {
        _checkFirstTimePermissions();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // When returning from Android settings, automatically refresh the checkmarks!
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      _refreshPermissionStatuses();
    }
  }

  Future<void> _refreshPermissionStatuses() async {
    try {
      final notif = await platform.invokeMethod<bool>('areNotificationsEnabled') ?? false;
      final bat = await platform.invokeMethod<bool>('isBatteryOptimizationIgnored') ?? false;

      if (mounted) {
        setState(() {
          _isNotifActive = notif;
          _isBatActive = bat;
        });
        _dialogSetState?.call(() {});
      }
    } catch (_) {}
  }

  Future<void> _checkFirstTimePermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasShownDialog = prefs.getBool('has_shown_battery_setup') ?? false;

    if (!hasShownDialog && mounted) {
      await _refreshPermissionStatuses();
      _showFirstTimeSetupDialog();
    }
  }

  void _showFirstTimeSetupDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          _dialogSetState = setModalState;

          return AlertDialog(
            backgroundColor: const Color(0xFF161D23),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF22BFA2), width: 1.5),
            ),
            title: const Row(
              children: [
                Icon(Icons.bolt, color: Color(0xFF22BFA2)),
                SizedBox(width: 8),
                Text(
                  'Background Setup',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'To let VoltMatch stream charging wattage with your screen turned off and chime at 80%, please enable these settings:',
                  style: TextStyle(color: Color(0xFFA7B0B9), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),

                // 1. Universal Notification Permission (Samsung A21s & iQOO Z6)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22BFA2).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.notifications_active, color: Color(0xFF22BFA2), size: 20),
                  ),
                  title: const Text('1. Notifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    _isNotifActive ? 'Active and enabled' : 'Required for Quick Tile & 80% chime',
                    style: TextStyle(fontSize: 11, color: _isNotifActive ? const Color(0xFF2ECC91) : const Color(0xFFA7B0B9)),
                  ),
                  trailing: _isNotifActive
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2ECC91).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, size: 14, color: Color(0xFF2ECC91)),
                              SizedBox(width: 4),
                              Text('Active', style: TextStyle(color: Color(0xFF2ECC91), fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF22BFA2),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          onPressed: () async {
                            await platform.invokeMethod('requestNotificationPermission');
                          },
                          child: const Text('Enable', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                ),

                const Divider(color: Colors.white10),

                // 2. Unrestricted Battery
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3DDDB5).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.battery_charging_full, color: Color(0xFF3DDDB5), size: 20),
                  ),
                  title: const Text('2. Unrestricted Battery', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    _isBatActive ? 'Battery is unrestricted' : 'Stops Android from putting Wi-Fi to sleep',
                    style: TextStyle(fontSize: 11, color: _isBatActive ? const Color(0xFF2ECC91) : const Color(0xFFA7B0B9)),
                  ),
                  trailing: _isBatActive
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2ECC91).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, size: 14, color: Color(0xFF2ECC91)),
                              SizedBox(width: 4),
                              Text('Active', style: TextStyle(color: Color(0xFF2ECC91), fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3DDDB5),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          onPressed: () async {
                            await platform.invokeMethod('requestIgnoreBatteryOptimization');
                          },
                          child: const Text('Set', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                ),

                const Divider(color: Colors.white10),

                // 3. App Settings ("Pause if unused")
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.settings, color: Colors.white70, size: 20),
                  ),
                  title: const Text('3. App Settings', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Turn off "Pause activity if unused"', style: TextStyle(fontSize: 11, color: Color(0xFFA7B0B9))),
                  trailing: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    onPressed: () {
                      platform.invokeMethod('openAppInfoSettings');
                    },
                    child: const Text('Open', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('has_shown_battery_setup', true);
                  _dialogSetState = null;
                  if (mounted) Navigator.pop(ctx);
                },
                child: const Text(
                  'Done / Continue',
                  style: TextStyle(color: Color(0xFF22BFA2), fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF22BFA2).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt, color: Color(0xFF22BFA2)),
            ),
            const SizedBox(width: 10),
            const Text(
              'VoltMatch',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Past Checks',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 12),
              Text(
                'Find Your Perfect Power Match.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Know safely if your USB-C charger and cable will power your phone or laptop.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFFA7B0B9),
                ),
              ),
              const SizedBox(height: 28),

              // 1. Compatibility Calculator
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SelectionScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C252C),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF22BFA2).withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22BFA2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.electric_bolt,
                          color: Colors.black,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Check Compatibility',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Pick device, charger & cable in 3 steps',
                              style: TextStyle(
                                color: Color(0xFFA7B0B9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Color(0xFF22BFA2),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 2. Live Meter & Cable Tester
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LiveTesterScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161D23),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF3DDDB5).withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3DDDB5).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.speed,
                          color: Color(0xFF3DDDB5),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Live Meter & Cable Tester',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Measure real-time Watts & check data wires',
                              style: TextStyle(
                                color: Color(0xFFA7B0B9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Color(0xFF3DDDB5),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 3. Remote Monitor
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RemoteMonitorScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161D23),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF22BFA2).withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22BFA2).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.wifi_tethering,
                          color: Color(0xFF22BFA2),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Remote Screen-Off Monitor',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Stream charging wattage to PC with screen off',
                              style: TextStyle(
                                color: Color(0xFFA7B0B9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Color(0xFF22BFA2),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Educational Tip Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF161D23),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.lightbulb_outline,
                          color: Color(0xFF3DDDB5),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Did You Know?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF3DDDB5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'USB Power Delivery is safe by design. A 100W charger will NOT force 100W into an 18W phone. The phone only requests and pulls what it can handle safely.',
                      style: TextStyle(color: Color(0xFFA7B0B9), height: 1.4),
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
}