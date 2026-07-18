import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/environmental_impact_repository.dart';
import '../domain/environmental_impact.dart';

class SustainabilityDashboardScreen extends StatelessWidget {
  const SustainabilityDashboardScreen({
    super.key,
    required this.repository,
    required this.currentUserId,
    required this.canSaveReports,
  });

  final EnvironmentalImpactRepository repository;
  final String currentUserId;
  final bool canSaveReports;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sustainability dashboard')),
    body: StreamBuilder<EnvironmentalImpactSnapshot>(
      stream: repository.watchImpact(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to calculate environmental impact: ${snapshot.error}',
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final impact = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Environmental impact',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => _printReport(impact),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: 'Environmental impact report',
                ),
                if (canSaveReports) ...[
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => _saveReport(context, impact),
                    icon: const Icon(Icons.archive_outlined),
                    tooltip: 'Save report snapshot',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _impactCard(
                  'E-waste collected',
                  impact.totalCollectedKg,
                  'kg',
                  Icons.scale_outlined,
                ),
                _impactCard(
                  'Waste recycled',
                  impact.totalRecycledKg,
                  'kg',
                  Icons.recycling,
                ),
                _impactCard(
                  'Landfill diversion',
                  impact.landfillDiversionRate,
                  '%',
                  Icons.delete_outline,
                ),
                _impactCard(
                  'Materials recovered',
                  impact.materialsRecoveredKg,
                  'kg',
                  Icons.precision_manufacturing_outlined,
                ),
                _impactCard(
                  'Carbon avoided',
                  impact.carbonEmissionsAvoidedKg,
                  'kg CO₂e',
                  Icons.cloud_outlined,
                ),
                _impactCard(
                  'Energy saved',
                  impact.energySavedKwh,
                  'kWh',
                  Icons.bolt_outlined,
                ),
                _impactCard(
                  'Hazardous waste handled',
                  impact.hazardousSafelyHandledKg,
                  'kg',
                  Icons.health_and_safety_outlined,
                ),
                _impactCard(
                  'Reusable devices',
                  impact.reusableDevices.toDouble(),
                  'devices',
                  Icons.devices_other,
                ),
                _impactCard(
                  'Trees equivalent',
                  impact.treesEquivalent,
                  'tree-years',
                  Icons.park_outlined,
                ),
                _impactCard(
                  'Water pollution reduced',
                  impact.waterPollutionReductionLitres,
                  'litres est.',
                  Icons.water_drop_outlined,
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              'Monthly impact comparison',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _comparison(context, impact.currentMonth, impact.previousMonth),
            const SizedBox(height: 12),
            _monthlyBars(context, impact.monthly),
            const SizedBox(height: 22),
            Text(
              'Recovered material profile',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (impact.materialBreakdownKg.isEmpty)
              const ListTile(
                title: Text('No recovered materials recorded yet.'),
              ),
            for (final entry
                in impact.materialBreakdownKg.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: Text(_materialLabel(entry.key)),
                trailing: Text('${entry.value.toStringAsFixed(2)} kg'),
              ),
            const SizedBox(height: 18),
            Text(
              'Saved environmental reports',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<EnvironmentalImpactReport>>(
              stream: repository.watchReports(),
              builder: (context, reportSnapshot) {
                final reports =
                    reportSnapshot.data ?? const <EnvironmentalImpactReport>[];
                if (reports.isEmpty) {
                  return const ListTile(
                    title: Text('No report snapshots saved.'),
                  );
                }
                return Column(
                  children: [
                    for (final report in reports.take(12))
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(report.periodLabel),
                          subtitle: Text(
                            '${report.totalCollectedKg.toStringAsFixed(1)} kg collected • ${report.landfillDiversionRate.toStringAsFixed(1)}% diverted',
                          ),
                          trailing: Text(
                            '${report.carbonAvoidedKg.toStringAsFixed(1)} kg CO₂e',
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Carbon, energy, trees-equivalent, and water-pollution figures are planning estimates calculated with EcoTrace impact factors v1. Operational weights and device counts come directly from verified system records.',
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _saveReport(
    BuildContext context,
    EnvironmentalImpactSnapshot impact,
  ) async {
    final now = impact.generatedAt;
    final period = '${_monthName(now.month)} ${now.year} impact snapshot';
    try {
      await repository.saveReport(
        impact,
        periodLabel: period,
        actorId: currentUserId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Environmental impact report saved.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save report: $error')),
        );
      }
    }
  }

  Future<void> _printReport(EnvironmentalImpactSnapshot impact) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(level: 0, text: 'EcoTrace Environmental Impact Report'),
          pw.Text('Generated: ${impact.generatedAt}'),
          pw.Text('Method: ${ImpactFactors.version}'),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const ['Impact measure', 'Result'],
            data: [
              [
                'Total e-waste collected',
                '${impact.totalCollectedKg.toStringAsFixed(2)} kg',
              ],
              [
                'Total waste recycled',
                '${impact.totalRecycledKg.toStringAsFixed(2)} kg',
              ],
              [
                'Landfill diversion rate',
                '${impact.landfillDiversionRate.toStringAsFixed(2)}%',
              ],
              [
                'Materials recovered',
                '${impact.materialsRecoveredKg.toStringAsFixed(2)} kg',
              ],
              [
                'Carbon emissions avoided',
                '${impact.carbonEmissionsAvoidedKg.toStringAsFixed(2)} kg CO2e',
              ],
              [
                'Energy saved',
                '${impact.energySavedKwh.toStringAsFixed(2)} kWh',
              ],
              [
                'Hazardous waste safely handled',
                '${impact.hazardousSafelyHandledKg.toStringAsFixed(2)} kg',
              ],
              ['Reusable devices recovered', '${impact.reusableDevices}'],
              [
                'Trees-equivalent estimate',
                '${impact.treesEquivalent.toStringAsFixed(2)} tree-years',
              ],
              [
                'Water pollution reduction estimate',
                '${impact.waterPollutionReductionLitres.toStringAsFixed(0)} litres',
              ],
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Header(level: 1, text: 'Recovered materials'),
          if (impact.materialBreakdownKg.isEmpty)
            pw.Text('No recovered material records.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Material', 'Recovered kg'],
              data: impact.materialBreakdownKg.entries
                  .map(
                    (entry) => [
                      _materialLabel(entry.key),
                      entry.value.toStringAsFixed(2),
                    ],
                  )
                  .toList(),
            ),
          pw.SizedBox(height: 14),
          pw.Header(level: 1, text: 'Monthly comparison'),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Month',
              'Collected kg',
              'Recycled kg',
              'Recovered kg',
              'CO2e avoided kg',
            ],
            data: impact.monthly
                .map(
                  (month) => [
                    '${_monthName(month.month.month)} ${month.month.year}',
                    month.collectedKg.toStringAsFixed(1),
                    month.recycledKg.toStringAsFixed(1),
                    month.materialsRecoveredKg.toStringAsFixed(1),
                    month.carbonAvoidedKg.toStringAsFixed(1),
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Estimated indicators are intended for sustainability planning and should be validated against locally approved lifecycle-assessment factors before regulatory use.',
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => document.save());
  }
}

Widget _impactCard(String label, double value, String unit, IconData icon) =>
    SizedBox(
      width: 178,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 8),
              Text(
                value.toStringAsFixed(unit == 'devices' ? 0 : 1),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(unit),
              const SizedBox(height: 4),
              Text(label),
            ],
          ),
        ),
      ),
    );

Widget _comparison(
  BuildContext context,
  MonthlyEnvironmentalImpact? current,
  MonthlyEnvironmentalImpact? previous,
) {
  if (current == null || previous == null) {
    return const Card(
      child: ListTile(title: Text('Monthly comparison is not available yet.')),
    );
  }
  Widget row(
    String label,
    double currentValue,
    double previousValue,
    String unit,
  ) {
    final change = currentValue - previousValue;
    final color = change >= 0
        ? Colors.green
        : Theme.of(context).colorScheme.error;
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text('Previous: ${previousValue.toStringAsFixed(1)} $unit'),
      trailing: Text(
        '${currentValue.toStringAsFixed(1)} $unit\n${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}',
        textAlign: TextAlign.end,
        style: TextStyle(color: color),
      ),
    );
  }

  return Card(
    child: Column(
      children: [
        ListTile(
          title: Text(
            '${_monthName(current.month.month)} ${current.month.year} versus ${_monthName(previous.month.month)} ${previous.month.year}',
          ),
        ),
        row(
          'E-waste collected',
          current.collectedKg,
          previous.collectedKg,
          'kg',
        ),
        row('Waste recycled', current.recycledKg, previous.recycledKg, 'kg'),
        row(
          'Materials recovered',
          current.materialsRecoveredKg,
          previous.materialsRecoveredKg,
          'kg',
        ),
        row(
          'Carbon avoided',
          current.carbonAvoidedKg,
          previous.carbonAvoidedKg,
          'kg CO₂e',
        ),
      ],
    ),
  );
}

Widget _monthlyBars(
  BuildContext context,
  List<MonthlyEnvironmentalImpact> months,
) {
  final maxValue = months.fold<double>(
    0,
    (maximum, month) =>
        month.collectedKg > maximum ? month.collectedKg : maximum,
  );
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          for (final month in months.skip(
            months.length > 6 ? months.length - 6 : 0,
          )) ...[
            Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    '${_monthName(month.month.month).substring(0, 3)} ${month.month.year}',
                  ),
                ),
                Expanded(
                  child: LinearProgressIndicator(
                    value: maxValue <= 0 ? 0 : month.collectedKg / maxValue,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: Text(
                    '${month.collectedKg.toStringAsFixed(1)} kg',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    ),
  );
}

String _materialLabel(String value) {
  if (value == 'circuitBoards') return 'Circuit boards';
  return value.isEmpty
      ? 'Other'
      : '${value[0].toUpperCase()}${value.substring(1)}';
}

String _monthName(int month) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][month - 1];
