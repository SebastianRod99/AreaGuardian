import 'dart:math' as math;

double distanceBetweenCoordinatesMeters({
  required double latitudeA,
  required double longitudeA,
  required double latitudeB,
  required double longitudeB,
}) {
  final latitudeARadians = latitudeA * math.pi / 180;
  final latitudeBRadians = latitudeB * math.pi / 180;
  final latitudeDelta = latitudeBRadians - latitudeARadians;
  final longitudeDelta = (longitudeB - longitudeA) * math.pi / 180;
  final haversine =
      math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(latitudeARadians) *
          math.cos(latitudeBRadians) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  return 6371000 * 2 * math.asin(math.sqrt(haversine.clamp(0.0, 1.0)));
}

bool isWithinRadiusMeters({
  required double latitudeA,
  required double longitudeA,
  required double latitudeB,
  required double longitudeB,
  required double radiusMeters,
}) {
  return distanceBetweenCoordinatesMeters(
        latitudeA: latitudeA,
        longitudeA: longitudeA,
        latitudeB: latitudeB,
        longitudeB: longitudeB,
      ) <=
      radiusMeters;
}
