import 'package:flutter/material.dart';
import '../models/power_models.dart';
import '../services/catalog_service.dart';
import '../services/compatibility_engine.dart';
import 'result_screen.dart';

class SelectionScreen extends StatefulWidget {
  const SelectionScreen({super.key});

  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen> {
  DeviceModel? selectedDevice;
  ChargerModel? selectedCharger;
  CableModel selectedCable = CatalogService.standardCables[0];

  String selectedDeviceBrand = 'All Brands';
  String selectedChargerBrand = 'All Brands';
  String deviceSearchQuery = '';
  String chargerSearchQuery = '';

  @override
  void initState() {
    super.initState();
    if (CatalogService.devices.isNotEmpty) {
      selectedDevice = CatalogService.devices[0];
    }
    if (CatalogService.chargers.isNotEmpty) {
      selectedCharger = CatalogService.chargers[0];
    }
  }

  List<String> get deviceBrands {
    final brands = CatalogService.devices.map((d) => d.manufacturer).toSet().toList();
    brands.sort();
    return ['All Brands', ...brands];
  }

  List<String> get chargerBrands {
    final brands = CatalogService.chargers.map((c) => c.manufacturer).toSet().toList();
    brands.sort();
    return ['All Brands', ...brands];
  }

  List<DeviceModel> get filteredDevices {
    return CatalogService.devices.where((d) {
      final matchesBrand = selectedDeviceBrand == 'All Brands' || d.manufacturer == selectedDeviceBrand;
      final matchesSearch = d.name.toLowerCase().contains(deviceSearchQuery.toLowerCase());
      return matchesBrand && matchesSearch;
    }).toList();
  }

  List<ChargerModel> get filteredChargers {
    return CatalogService.chargers.where((c) {
      final matchesBrand = selectedChargerBrand == 'All Brands' || c.manufacturer == selectedChargerBrand;
      final matchesSearch = c.name.toLowerCase().contains(chargerSearchQuery.toLowerCase());
      return matchesBrand && matchesSearch;
    }).toList();
  }

  void _addCustomDevice() {
    final nameCtrl = TextEditingController();
    final wattCtrl = TextEditingController(text: '30');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C252C),
        title: const Text('Add Custom Device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Device Name (e.g. My Phone)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: wattCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Recommended Power (Watts)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22BFA2),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final watts = double.tryParse(wattCtrl.text) ?? 20.0;
              final name = nameCtrl.text.trim().isEmpty ? 'Custom Device' : nameCtrl.text.trim();
              final newDevice = DeviceModel(
                id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                name: '$name (${watts.toStringAsFixed(0)}W)',
                manufacturer: 'Custom',
                category: 'phone',
                connector: 'USB-C',
                isVerified: false,
                recommendedPower: watts,
                minPower: watts * 0.4,
                acceptedProfiles: [
                  PowerProfile(voltage: 5.0, maxCurrent: 3.0),
                  PowerProfile(voltage: 9.0, maxCurrent: (watts / 9.0).clamp(1.0, 3.0)),
                  if (watts >= 30) PowerProfile(voltage: 20.0, maxCurrent: (watts / 20.0).clamp(1.5, 5.0)),
                ],
              );
              setState(() {
                CatalogService.devices.add(newDevice);
                selectedDevice = newDevice;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Add & Select'),
          ),
        ],
      ),
    );
  }

  void _addCustomCharger() {
    final nameCtrl = TextEditingController();
    final wattCtrl = TextEditingController(text: '45');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C252C),
        title: const Text('Add Custom Charger'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Charger Name (e.g. Power Brick)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: wattCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Max Power (Watts)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22BFA2),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final watts = double.tryParse(wattCtrl.text) ?? 30.0;
              final name = nameCtrl.text.trim().isEmpty ? 'Custom Charger' : nameCtrl.text.trim();
              final newCharger = ChargerModel(
                id: 'custom_chg_${DateTime.now().millisecondsSinceEpoch}',
                name: '$name (${watts.toStringAsFixed(0)}W)',
                manufacturer: 'Custom',
                maxAdvertisedPower: watts,
                isMultiport: false,
                isVerified: false,
                outputProfiles: [
                  PowerProfile(voltage: 5.0, maxCurrent: 3.0),
                  PowerProfile(voltage: 9.0, maxCurrent: 3.0),
                  if (watts >= 45) PowerProfile(voltage: 15.0, maxCurrent: 3.0),
                  if (watts >= 65) PowerProfile(voltage: 20.0, maxCurrent: (watts / 20.0).clamp(3.0, 5.0)),
                ],
              );
              setState(() {
                CatalogService.chargers.add(newCharger);
                selectedCharger = newCharger;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Add & Select'),
          ),
        ],
      ),
    );
  }

  void _runCheck() {
    if (selectedDevice == null || selectedCharger == null) return;

    final result = CompatibilityEngine.evaluate(
      device: selectedDevice!,
      charger: selectedCharger!,
      cable: selectedCable,
    );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configure Check')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 1. DEVICE SELECTION
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionTitle('1. Select Your Device', Icons.smartphone),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF3DDDB5)),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Custom'),
                    onPressed: _addCustomDevice,
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C252C),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    // Brand Filter (Full Width)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: selectedDeviceBrand,
                      dropdownColor: const Color(0xFF161D23),
                      decoration: const InputDecoration(
                        labelText: 'Brand / Company',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(),
                      ),
                      items: deviceBrands.map((b) {
                        return DropdownMenuItem(
                          value: b,
                          child: Text(b, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            selectedDeviceBrand = val;
                            if (filteredDevices.isNotEmpty) selectedDevice = filteredDevices[0];
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    // Search Filter (Full Width)
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search model (e.g. S24, 15 Pro, Z6)...',
                        prefixIcon: Icon(Icons.search, size: 20),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (text) => setState(() => deviceSearchQuery = text),
                    ),
                    const SizedBox(height: 12),
                    // Model Dropdown (Full Width)
                    DropdownButtonFormField<DeviceModel>(
                      isExpanded: true,
                      value: filteredDevices.contains(selectedDevice)
                          ? selectedDevice
                          : (filteredDevices.isNotEmpty ? filteredDevices[0] : null),
                      dropdownColor: const Color(0xFF161D23),
                      decoration: const InputDecoration(
                        labelText: 'Model / Variant',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(),
                      ),
                      items: filteredDevices.map((d) {
                        return DropdownMenuItem(
                          value: d,
                          child: Text(d.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => selectedDevice = val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 2. CHARGER SELECTION
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionTitle('2. Select Your Charger', Icons.power),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF3DDDB5)),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Custom'),
                    onPressed: _addCustomCharger,
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C252C),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    // Brand Filter (Full Width)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: selectedChargerBrand,
                      dropdownColor: const Color(0xFF161D23),
                      decoration: const InputDecoration(
                        labelText: 'Charger Brand',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(),
                      ),
                      items: chargerBrands.map((b) {
                        return DropdownMenuItem(
                          value: b,
                          child: Text(b, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            selectedChargerBrand = val;
                            if (filteredChargers.isNotEmpty) selectedCharger = filteredChargers[0];
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    // Search Filter (Full Width)
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search charger (e.g. 65W, Anker, FlashCharge)...',
                        prefixIcon: Icon(Icons.search, size: 20),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (text) => setState(() => chargerSearchQuery = text),
                    ),
                    const SizedBox(height: 12),
                    // Model Dropdown (Full Width)
                    DropdownButtonFormField<ChargerModel>(
                      isExpanded: true,
                      value: filteredChargers.contains(selectedCharger)
                          ? selectedCharger
                          : (filteredChargers.isNotEmpty ? filteredChargers[0] : null),
                      dropdownColor: const Color(0xFF161D23),
                      decoration: const InputDecoration(
                        labelText: 'Charger Model / Wattage',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(),
                      ),
                      items: filteredChargers.map((c) {
                        return DropdownMenuItem(
                          value: c,
                          child: Text(c.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => selectedCharger = val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 3. CABLE SELECTION
              _buildSectionTitle('3. Select Cable Type', Icons.cable),
              ...CatalogService.standardCables.map((cable) {
                final isSelected = selectedCable.id == cable.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ListTile(
                    tileColor: isSelected ? const Color(0xFF1C252C) : const Color(0xFF161D23),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF22BFA2) : Colors.white10,
                      ),
                    ),
                    leading: Icon(
                      Icons.cable,
                      color: isSelected ? const Color(0xFF22BFA2) : Colors.grey,
                    ),
                    title: Text(cable.name, style: const TextStyle(fontSize: 14)),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF22BFA2)) : null,
                    onTap: () => setState(() => selectedCable = cable),
                  ),
                );
              }),

              const SizedBox(height: 32),

              // CHECK BUTTON
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22BFA2),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _runCheck,
                  child: const Text(
                    'Check Compatibility Now',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF3DDDB5)),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}