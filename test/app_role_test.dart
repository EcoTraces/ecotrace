import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/auth/domain/app_role.dart';

void main() {
  group('AppRole', () {
    test('only low-privilege roles support self-registration', () {
      expect(AppRole.selfServiceRoles, [
        AppRole.household,
        AppRole.business,
        AppRole.institution,
      ]);
      expect(AppRole.selfServiceRoles.contains(AppRole.administrator), isFalse);
      expect(
        AppRole.selfServiceRoles.contains(AppRole.superAdministrator),
        isFalse,
      );
    });

    test('unknown stored roles fall back to household', () {
      expect(AppRole.fromValue('unknown'), AppRole.household);
    });
  });
}
