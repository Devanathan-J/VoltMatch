import 'power_models.dart';

enum CompatibilityStatus {
  compatible,
  limited,
  incompatible,
  cannotVerify,
}

class CompatibilityResult {
  final CompatibilityStatus status;
  final DeviceModel device;
  final ChargerModel charger;
  final CableModel cable;
  final PowerProfile? matchedProfile;
  final double availablePower;
  final String summaryTitle;
  final String explanation;
  final List<String> warnings;
  final List<String> calculationSteps;
  final DateTime timestamp;

  CompatibilityResult({
    required this.status,
    required this.device,
    required this.charger,
    required this.cable,
    this.matchedProfile,
    required this.availablePower,
    required this.summaryTitle,
    required this.explanation,
    required this.warnings,
    required this.calculationSteps,
    required this.timestamp,
  });
}