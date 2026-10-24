import 'package:flutter/material.dart';
import '../models/compatibility_result.dart';
import '../services/history_service.dart';

class ResultScreen extends StatelessWidget {
  final CompatibilityResult result;

  const ResultScreen({super.key, required this.result});

  Color _getStatusColor() {
    switch (result.status) {
      case CompatibilityStatus.compatible:
        return const Color(0xFF2ECC91);
      case CompatibilityStatus.limited:
        return const Color(0xFFF5B544);
      case CompatibilityStatus.incompatible:
        return const Color(0xFFEF6464);
      case CompatibilityStatus.cannotVerify:
        return const Color(0xFFA7B0B9);
    }
  }

  IconData _getStatusIcon() {
    switch (result.status) {
      case CompatibilityStatus.compatible:
        return Icons.check_circle;
      case CompatibilityStatus.limited:
        return Icons.warning_amber_rounded;
      case CompatibilityStatus.incompatible:
        return Icons.cancel_outlined;
      case CompatibilityStatus.cannotVerify:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();

    return Scaffold(
      appBar: AppBar(title: const Text('Compatibility Result')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Status Hero Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C252C),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusColor, width: 2),
                ),
                child: Column(
                  children: [
                    Icon(_getStatusIcon(), size: 56, color: statusColor),
                    const SizedBox(height: 12),
                    Text(
                      result.summaryTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      result.explanation,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFA7B0B9), height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    // Power Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Negotiated Power: ${result.availablePower.toStringAsFixed(1)} Watts',
                        style: TextStyle(fontWeight: FontWeight.bold, color: statusColor),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Overview Cards
              Row(
                children: [
                  Expanded(
                    child: _infoCard('Device', result.device.name, '${result.device.recommendedPower.toStringAsFixed(0)}W req'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _infoCard('Charger', result.charger.name, '${result.charger.maxAdvertisedPower.toStringAsFixed(0)}W rated'),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Warnings
              if (result.warnings.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5B544).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF5B544).withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning, color: Color(0xFFF5B544), size: 18),
                          SizedBox(width: 8),
                          Text('Important Notes', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF5B544))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...result.warnings.map((w) => Text('• $w', style: const TextStyle(color: Color(0xFFA7B0B9)))),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Technical Details Accordion
              ExpansionTile(
                title: const Text('How was this calculated?', style: TextStyle(fontWeight: FontWeight.bold)),
                children: result.calculationSteps.map((step) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.arrow_right, color: Color(0xFF22BFA2)),
                    title: Text(step, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFFA7B0B9))),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Actions
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22BFA2),
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.save_alt),
                label: const Text('Save Comparison to History'),
                onPressed: () async {
                  await HistoryService.save(
                    HistoryItem(
                      deviceName: result.device.name,
                      chargerName: result.charger.name,
                      cableName: result.cable.name,
                      status: result.status.name,
                      power: result.availablePower,
                      date: DateTime.now(),
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Saved to your history!')),
                  );
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Test Another Combination'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard(String label, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161D23),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF3DDDB5))),
        ],
      ),
    );
  }
}