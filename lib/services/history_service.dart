import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryItem {
  final String deviceName;
  final String chargerName;
  final String cableName;
  final String status;
  final double power;
  final DateTime date;

  HistoryItem({
    required this.deviceName,
    required this.chargerName,
    required this.cableName,
    required this.status,
    required this.power,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
    'deviceName': deviceName,
    'chargerName': chargerName,
    'cableName': cableName,
    'status': status,
    'power': power,
    'date': date.toIso8601String(),
  };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    deviceName: json['deviceName'] ?? '',
    chargerName: json['chargerName'] ?? '',
    cableName: json['cableName'] ?? '',
    status: json['status'] ?? '',
    power: (json['power'] as num).toDouble(),
    date: DateTime.parse(json['date']),
  );
}

class HistoryService {
  static const _key = 'voltmatch_history';

  static Future<void> save(HistoryItem item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> list = prefs.getStringList(_key) ?? [];
      list.insert(0, json.encode(item.toJson()));
      if (list.length > 20) list = list.sublist(0, 20);
      await prefs.setStringList(_key, list);
    } catch (_) {}
  }

  static Future<List<HistoryItem>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? [];
      return list.map((e) => HistoryItem.fromJson(json.decode(e))).toList();
    } catch (_) {
      return [];
    }
  }

  // Delete a single item
  static Future<void> deleteAt(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> list = prefs.getStringList(_key) ?? [];
      if (index >= 0 && index < list.length) {
        list.removeAt(index);
        await prefs.setStringList(_key, list);
      }
    } catch (_) {}
  }

  // Clear all items
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}