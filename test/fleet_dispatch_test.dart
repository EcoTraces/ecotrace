import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/dispatch/domain/collection_schedule.dart';
import 'package:wastemanagementsystem/features/fleet/domain/vehicle.dart';

void main() {
  test('dispatch lifecycle covers missed and completed jobs', () {
    expect(
      DispatchStatus.values,
      containsAll([
        DispatchStatus.planned,
        DispatchStatus.missed,
        DispatchStatus.completed,
      ]),
    );
  });
  test('fleet availability distinguishes operational failures', () {
    expect(
      VehicleAvailability.values,
      containsAll([
        VehicleAvailability.available,
        VehicleAvailability.maintenance,
        VehicleAvailability.breakdown,
      ]),
    );
  });
}
