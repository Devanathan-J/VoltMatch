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

  @override
  void initState() {
    super.initState();
    if (CatalogService.devices.isNotEmpty) {
      selectedDevice = CatalogService.devices[0];
    }
    if (CatalogService.chargers.isNotEmpty) {
      selectedCharger = CatalogService.chargers[1]; // default to 65W
    }
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
              // 1. Device Picker
              _buildSectionTitle('1. Select Your Device', Icons.smartphone),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C252C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<DeviceModel>(
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1C252C),
                    value: selectedDevice,
                    items: CatalogService.devices.map((d) {
                      return DropdownMenuItem(
                        value: d,
                        child: Text('${d.name} (${d.recommendedPower.toStringAsFixed(0)}W req)'),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => selectedDevice = val),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 2. Charger Picker
              _buildSectionTitle('2. Select Your Charger', Icons.power),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C252C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ChargerModel>(
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1C252C),
                    value: selectedCharger,
                    items: CatalogService.chargers.map((c) {
                      return DropdownMenuItem(
                        value: c,
                        child: Text('${c.name} (${c.maxAdvertisedPower.toStringAsFixed(0)}W max)'),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => selectedCharger = val),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 3. Cable Picker
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
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Color(0xFF22BFA2))
                        : null,
                    onTap: () => setState(() => selectedCable = cable),
                  ),
                );
              }),

              const SizedBox(height: 32),

              // Action Button
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22BFA2),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _runCheck,
                  child: const Text('Check Compatibility Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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