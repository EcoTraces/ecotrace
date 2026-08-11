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

class DashboardWidgetConfig {
  const DashboardWidgetConfig({
    required this.id,
    required this.title,
    required this.metric,
    required this.visualization,
    required this.roles,
    required this.order,
    required this.active,
  });
  final String id, title, metric, visualization;
  final List<String> roles;
  final int order;
  final bool active;

  static const metrics = [
    'collections',
    'weight',
    'recyclingRate',
    'recoveryRate',
    'revenue',
    'users',
    'partners',
    'environmentalImpact',
  ];
  static const visualizations = ['number', 'line', 'bar', 'pie', 'table', 'map'];

  factory DashboardWidgetConfig.fromJson(Map<String, dynamic> data) =>
      DashboardWidgetConfig(
        id: (data['id'] ?? '').toString(),
        title: (data['title'] ?? '').toString(),
        metric: (data['metric'] ?? metrics.first).toString(),
        visualization: (data['visualization'] ?? visualizations.first)
            .toString(),
        roles: List<String>.from(data['roles'] as List? ?? const []),
        order: (data['order'] as num? ?? 0).toInt(),
        active: data['active'] != false,
      );
}

class ReportDefinition {
  const ReportDefinition({
    required this.id,
    required this.name,
    required this.type,
    required this.fields,
    required this.groupBy,
    required this.metrics,
    required this.active,
  });
  final String id, name, groupBy;
  final ReportType type;
  final List<String> fields, metrics;
  final bool active;

  static const availableMetrics = [
    'count',
    'sum',
    'average',
    'minimum',
    'maximum',
  ];

  factory ReportDefinition.fromJson(Map<String, dynamic> data) =>
      ReportDefinition(
        id: (data['id'] ?? '').toString(),
        name: (data['name'] ?? '').toString(),
        type:
            ReportType.values
                .where((value) => value.name == data['type'])
                .firstOrNull ??
            ReportType.custom,
        fields: List<String>.from(data['fields'] as List? ?? const []),
        groupBy: (data['groupBy'] ?? '').toString(),
        metrics: List<String>.from(
          data['metrics'] as List? ?? const ['count'],
        ),
        active: data['active'] != false,
      );
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
