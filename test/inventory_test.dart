import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/inventory/domain/inventory_item.dart';

void main() {
  test('all required conditions exist', () {
    expect(ItemCondition.values, hasLength(7));
  });
  test('processing lifecycle supports recovery and quarantine', () {
    expect(
      ProcessingStatus.values,
      containsAll([ProcessingStatus.recovered, ProcessingStatus.quarantined]),
    );
  });
}
