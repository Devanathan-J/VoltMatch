import 'dart:math';
import '../models/power_models.dart';
import '../models/compatibility_result.dart';

class CompatibilityEngine {
  static CompatibilityResult evaluate({
    required DeviceModel device,
    required ChargerModel charger,
    required CableModel cable,
  }) {
    List<String> steps = [];
    List<String> warnings = [];

    // Step 1: Input Validation
    if (cable.currentRating <= 0) {
      return CompatibilityResult(
        status: CompatibilityStatus.cannotVerify,
        device: device,
        charger: charger,
        cable: cable,
        availablePower: 0,
        summaryTitle: 'Cannot Verify Cable Capability',
        explanation: 'The cable specifications are unknown. High-power USB-C charging requires a verified 3A or 5A cable rating to ensure safe negotiation.',
        warnings: ['Using an unrated or damaged cable may cause slow charging or heat build-up.'],
        calculationSteps: ['Failed at Step 1: Unknown cable capability.'],
        timestamp: DateTime.now(),
      );
    }

    steps.add('Cable verified for up to ${cable.currentRating.toStringAsFixed(0)} Amperes.');

    // Step 2: Voltage Matching
    PowerProfile? bestDeviceProfile;
    PowerProfile? bestChargerProfile;
    double maxCandidatePower = 0.0;

    for (var devProf in device.acceptedProfiles) {
      for (var chgProf in charger.outputProfiles) {
        if ((devProf.voltage - chgProf.voltage).abs() < 0.2) {
          // Candidate matched profile
          double allowedCurrent = [
            devProf.maxCurrent,
            chgProf.maxCurrent,
            cable.currentRating,
          ].reduce(min);

          double power = devProf.voltage * allowedCurrent;

          if (power > maxCandidatePower) {
            maxCandidatePower = power;
            bestDeviceProfile = devProf;
            bestChargerProfile = chgProf;
          }
        }
      }
    }

    if (bestDeviceProfile == null || bestChargerProfile == null) {
      return CompatibilityResult(
        status: CompatibilityStatus.incompatible,
        device: device,
        charger: charger,
        cable: cable,
        availablePower: 0,
        summaryTitle: 'No Matching Fixed USB-PD Voltage Profile',
        explanation: 'Your device and charger do not share any supported common USB-PD voltage levels. Negotiation cannot proceed safely.',
        warnings: ['The device will refuse to charge or charge at emergency 5V low current.'],
        calculationSteps: [
          'Evaluated ${device.acceptedProfiles.length} device profiles against ${charger.outputProfiles.length} charger profiles.',
          'Result: No matching voltage found.',
        ],
        timestamp: DateTime.now(),
      );
    }

    double matchedVoltage = bestDeviceProfile.voltage;
    double negotiatedCurrent = [
      bestDeviceProfile.maxCurrent,
      bestChargerProfile.maxCurrent,
      cable.currentRating,
    ].reduce(min);

    double negotiatedPower = matchedVoltage * negotiatedCurrent;

    steps.add('Matched Fixed Voltage: ${matchedVoltage.toStringAsFixed(0)}V');
    steps.add('Device requests up to ${bestDeviceProfile.maxCurrent}A, Charger supplies up to ${bestChargerProfile.maxCurrent}A, Cable allows ${cable.currentRating}A.');
    steps.add('Negotiated Current Limit = min(${bestDeviceProfile.maxCurrent}A, ${bestChargerProfile.maxCurrent}A, ${cable.currentRating}A) = ${negotiatedCurrent}A');
    steps.add('Total Negotiated Power = $matchedVoltage V × $negotiatedCurrent A = ${negotiatedPower.toStringAsFixed(1)}W');

    if (cable.currentRating < bestChargerProfile.maxCurrent && cable.currentRating < bestDeviceProfile.maxCurrent) {
      warnings.add('Your cable (rated ${cable.currentRating}A) is capping the maximum speed. A 5A cable would deliver higher wattage.');
    }

    if (charger.isMultiport) {
      warnings.add('This is a multiport charger. Plugging in multiple devices will reduce single-port power delivery.');
    }

    // Step 3: Classification against requirements
    if (negotiatedPower >= device.recommendedPower) {
      return CompatibilityResult(
        status: CompatibilityStatus.compatible,
        device: device,
        charger: charger,
        cable: cable,
        matchedProfile: PowerProfile(voltage: matchedVoltage, maxCurrent: negotiatedCurrent),
        availablePower: negotiatedPower,
        summaryTitle: 'Compatible Under Stated Conditions',
        explanation: 'The charger delivers ${negotiatedPower.toStringAsFixed(0)}W at ${matchedVoltage.toStringAsFixed(0)}V, meeting or exceeding your device\'s recommended ${device.recommendedPower.toStringAsFixed(0)}W requirement.',
        warnings: warnings,
        calculationSteps: steps,
        timestamp: DateTime.now(),
      );
    } else if (negotiatedPower >= device.minPower) {
      return CompatibilityResult(
        status: CompatibilityStatus.limited,
        device: device,
        charger: charger,
        cable: cable,
        matchedProfile: PowerProfile(voltage: matchedVoltage, maxCurrent: negotiatedCurrent),
        availablePower: negotiatedPower,
        summaryTitle: 'Limited / Slower Charging',
        explanation: 'Charging is electrically compatible at ${negotiatedPower.toStringAsFixed(1)}W, but this is below the recommended ${device.recommendedPower.toStringAsFixed(0)}W. Charging may be slower or drain during intense use.',
        warnings: warnings,
        calculationSteps: steps,
        timestamp: DateTime.now(),
      );
    } else {
      return CompatibilityResult(
        status: CompatibilityStatus.limited,
        device: device,
        charger: charger,
        cable: cable,
        matchedProfile: PowerProfile(voltage: matchedVoltage, maxCurrent: negotiatedCurrent),
        availablePower: negotiatedPower,
        summaryTitle: 'Insufficient Power (Very Slow or Idle Only)',
        explanation: 'The negotiated power (${negotiatedPower.toStringAsFixed(1)}W) is below the minimum ${device.minPower.toStringAsFixed(0)}W threshold documented for this device.',
        warnings: [
          'The device might display "Plugged in, not charging" or slowly lose battery while on.',
          ...warnings,
        ],
        calculationSteps: steps,
        timestamp: DateTime.now(),
      );
    }
  }
}