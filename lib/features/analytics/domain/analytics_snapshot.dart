enum ReportType {
  collection,
  pickup,
  inventory,
  recycling,
  repair,
  resourceRecovery,
  environmentalImpact,
  user,
  partner,
  financial,
  compliance,
  incident,
  custom,
}

class AnalyticsSnapshot {
  const AnalyticsSnapshot({
    required this.from,
    required this.to,
    required this.metrics,
    required this.categories,
    required this.regions,
    required this.rows,
  });
  final DateTime from, to;
  final Map<String, double> metrics;
  final Map<String, double> categories, regions;
  final List<Map<String, Object?>> rows;
  double value(String key) => metrics[key] ?? 0;
}

class ReportSchedule {
  const ReportSchedule({
    required this.id,
    required this.name,
    required this.type,
    required this.frequency,
    required this.recipients,
    required this.active,
  });
  final String id, name, frequency;
  final ReportType type;
  final List<String> recipients;
  final bool active;
  factory ReportSchedule.fromJson(Map<String, dynamic> data) => ReportSchedule(
    id: data['id']?.toString() ?? '',
    name: data['name']?.toString() ?? 'Scheduled report',
    type: ReportType.values.where((value) => value.name == data['type']).firstOrNull ?? ReportType.custom,
    frequency: data['frequency']?.toString() ?? 'monthly',
    recipients: List<String>.from(data['recipientEmails'] as List? ?? data['recipients'] as List? ?? const []),
    active: data['active'] != false,
  );
}
