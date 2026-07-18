import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/routing/data/route_repository.dart';

void main() {
  test('haversine distance is zero for the same point', () {
    expect(RouteRepository.distanceKm(1, 2, 1, 2), closeTo(0, .0001));
  });

  test('haversine estimates a known equatorial degree', () {
    expect(RouteRepository.distanceKm(0, 0, 0, 1), closeTo(111.2, .5));
  });
}
