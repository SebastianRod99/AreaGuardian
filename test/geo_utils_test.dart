import 'package:areaguardian/utils/geo_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calcula el límite de 300 metros alrededor de Fontibón', () {
    const latitude = 4.678;
    const longitude = -74.140;
    final insideLatitude = latitude + 250 / 111320;
    final outsideLatitude = latitude + 350 / 111320;

    expect(
      isWithinRadiusMeters(
        latitudeA: latitude,
        longitudeA: longitude,
        latitudeB: insideLatitude,
        longitudeB: longitude,
        radiusMeters: 300,
      ),
      isTrue,
    );
    expect(
      isWithinRadiusMeters(
        latitudeA: latitude,
        longitudeA: longitude,
        latitudeB: outsideLatitude,
        longitudeB: longitude,
        radiusMeters: 300,
      ),
      isFalse,
    );
  });

  test(
    'acepta una emergencia cercana y rechaza una situada a dos kilómetros',
    () {
      expect(
        isWithinRadiusMeters(
          latitudeA: 4.678,
          longitudeA: -74.140,
          latitudeB: 4.678 + 200 / 111320,
          longitudeB: -74.140,
          radiusMeters: 300,
        ),
        isTrue,
      );
      expect(
        isWithinRadiusMeters(
          latitudeA: 4.678,
          longitudeA: -74.140,
          latitudeB: 4.678 + 2000 / 111320,
          longitudeB: -74.140,
          radiusMeters: 300,
        ),
        isFalse,
      );
    },
  );
}
