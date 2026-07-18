import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/organizations/domain/organization.dart';

void main() {
  group('Organization model values', () {
    test('supports all production registration types', () {
      expect(OrganizationType.values, hasLength(5));
      expect(
        OrganizationType.fromValue('collectionCompany'),
        OrganizationType.collectionCompany,
      );
    });

    test('unknown status has a safe draft fallback', () {
      expect(OrganizationStatus.fromValue('unknown'), OrganizationStatus.draft);
    });
  });
}
