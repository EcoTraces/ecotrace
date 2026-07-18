import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/analytics/domain/analytics_snapshot.dart';

void main() {
  test('analytics exposes date-filtered KPI values', () {
    final x = AnalyticsSnapshot(
      from: DateTime(2026),
      to: DateTime(2026, 2),
      metrics: const {'recyclingRate': 80},
      categories: const {},
      regions: const {},
      rows: const [],
    );
    expect(x.value('recyclingRate'), 80);
    expect(x.value('missing'), 0);
  });
  test(
    'report catalogue covers operational financial regulatory and academic data',
    () {
      expect(
        ReportType.values,
        containsAll([
          ReportType.collection,
          ReportType.pickup,
          ReportType.inventory,
          ReportType.recycling,
          ReportType.repair,
          ReportType.resourceRecovery,
          ReportType.environmentalImpact,
          ReportType.user,
          ReportType.partner,
          ReportType.financial,
          ReportType.compliance,
          ReportType.incident,
          ReportType.custom,
        ]),
      );
    },
  );
}
