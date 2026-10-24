import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/power_models.dart';

class CatalogService {
  static List<DeviceModel> devices = [];
  static List<ChargerModel> chargers = [];

  static final List<CableModel> standardCables = [
    CableModel(id: 'cbl_3a', name: 'Standard USB-C Cable (3A / 60W)', currentRating: 3.0),
    CableModel(id: 'cbl_5a', name: 'High-Power USB-C Cable (5A / 100W)', currentRating: 5.0),
    CableModel(id: 'cbl_unk', name: 'Unknown / Generic Cable (Unverified)', currentRating: 0.0, isVerified: false),
  ];

  static Future<void> loadCatalog() async {
    try {
      final devStr = await rootBundle.loadString('assets/data/devices.json');
      final List devList = json.decode(devStr);
      devices = devList.map((d) => DeviceModel.fromJson(d)).toList();

      final chgStr = await rootBundle.loadString('assets/data/chargers.json');
      final List chgList = json.decode(chgStr);
      chargers = chgList.map((c) => ChargerModel.fromJson(c)).toList();
    } catch (e) {
      // Fallback defaults if assets fail
      devices = [
        DeviceModel(
          id: 'dev_demo_phone',
          name: 'Demo Smartphone',
          manufacturer: 'Standard',
          category: 'phone',
          connector: 'USB-C',
          isVerified: true,
          recommendedPower: 20.0,
          minPower: 10.0,
          acceptedProfiles: [PowerProfile(voltage: 9.0, maxCurrent: 2.22)],
        )
      ];
      chargers = [
        ChargerModel(
          id: 'chg_demo',
          name: 'Demo 65W Charger',
          manufacturer: 'VoltMatch',
          maxAdvertisedPower: 65.0,
          isMultiport: false,
          isVerified: true,
          outputProfiles: [
            PowerProfile(voltage: 9.0, maxCurrent: 3.0),
            PowerProfile(voltage: 20.0, maxCurrent: 3.25),
          ],
        )
      ];
    }
  }
}