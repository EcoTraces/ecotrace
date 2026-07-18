import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/classification/domain/assessment.dart';

void main() {
  test('all classification categories are represented', () {
    expect(DeviceCategory.values, hasLength(10));
  });
  test('treatment outcomes include reuse through disposal', () {
    expect(
      TreatmentRecommendation.values,
      containsAll([
        TreatmentRecommendation.reuse,
        TreatmentRecommendation.repair,
        TreatmentRecommendation.recycle,
        TreatmentRecommendation.finalDisposal,
      ]),
    );
  });
}
