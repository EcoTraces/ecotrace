import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/core/app_features.dart';
import 'package:wastemanagementsystem/features/pickups/domain/pickup.dart';

void main() {
  test('pickup fee includes urgent surcharge', () {
    expect(estimatePickupFee(quantity: 2, weight: 4, urgent: true), 22);
  });
  test('production lifecycle statuses are represented', () {
    expect(PickupStatus.values, hasLength(10));
  });
  test('Firebase Storage uploads are disabled for the default Spark build', () {
    expect(AppFeatures.firebaseStorageUploadsEnabled, isFalse);
  });
}
