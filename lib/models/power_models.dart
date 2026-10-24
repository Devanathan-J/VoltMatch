class PowerProfile {
  final double voltage;
  final double maxCurrent;

  PowerProfile({required this.voltage, required this.maxCurrent});

  double get power => voltage * maxCurrent;

  factory PowerProfile.fromJson(Map<String, dynamic> json) {
    return PowerProfile(
      voltage: (json['voltage'] as num).toDouble(),
      maxCurrent: (json['maxCurrent'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'voltage': voltage,
    'maxCurrent': maxCurrent,
  };
}

class DeviceModel {
  final String id;
  final String name;
  final String manufacturer;
  final String category; // 'phone' or 'laptop'
  final String connector;
  final bool isVerified;
  final double recommendedPower;
  final double minPower;
  final List<PowerProfile> acceptedProfiles;
  final List<String> modelCodes; // <-- Added from MobileModels database!

  DeviceModel({
    required this.id,
    required this.name,
    required this.manufacturer,
    required this.category,
    required this.connector,
    required this.isVerified,
    required this.recommendedPower,
    required this.minPower,
    required this.acceptedProfiles,
    this.modelCodes = const [],
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'],
      name: json['name'],
      manufacturer: json['manufacturer'],
      category: json['category'],
      connector: json['connector'],
      isVerified: json['isVerified'] ?? false,
      recommendedPower: (json['recommendedPower'] as num).toDouble(),
      minPower: (json['minPower'] as num).toDouble(),
      acceptedProfiles: (json['acceptedProfiles'] as List)
          .map((p) => PowerProfile.fromJson(p))
          .toList(),
      modelCodes: json['modelCodes'] != null
          ? List<String>.from(json['modelCodes'])
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'manufacturer': manufacturer,
    'category': category,
    'connector': connector,
    'isVerified': isVerified,
    'recommendedPower': recommendedPower,
    'minPower': minPower,
    'acceptedProfiles': acceptedProfiles.map((p) => p.toJson()).toList(),
    'modelCodes': modelCodes,
  };
}

class ChargerModel {
  final String id;
  final String name;
  final String manufacturer;
  final double maxAdvertisedPower;
  final bool isMultiport;
  final bool isVerified;
  final List<PowerProfile> outputProfiles;

  ChargerModel({
    required this.id,
    required this.name,
    required this.manufacturer,
    required this.maxAdvertisedPower,
    required this.isMultiport,
    required this.isVerified,
    required this.outputProfiles,
  });

  factory ChargerModel.fromJson(Map<String, dynamic> json) {
    return ChargerModel(
      id: json['id'],
      name: json['name'],
      manufacturer: json['manufacturer'],
      maxAdvertisedPower: (json['maxAdvertisedPower'] as num).toDouble(),
      isMultiport: json['isMultiport'] ?? false,
      isVerified: json['isVerified'] ?? false,
      outputProfiles: (json['outputProfiles'] as List)
          .map((p) => PowerProfile.fromJson(p))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'manufacturer': manufacturer,
    'maxAdvertisedPower': maxAdvertisedPower,
    'isMultiport': isMultiport,
    'isVerified': isVerified,
    'outputProfiles': outputProfiles.map((p) => p.toJson()).toList(),
  };
}

class CableModel {
  final String id;
  final String name;
  final double currentRating;
  final bool isVerified;

  CableModel({
    required this.id,
    required this.name,
    required this.currentRating,
    this.isVerified = true,
  });
}