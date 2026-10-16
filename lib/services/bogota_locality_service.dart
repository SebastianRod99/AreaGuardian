import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class BogotaLocalityService {
  BogotaLocalityService._(this._polygons);

  static Future<BogotaLocalityService>? _instance;

  final List<_LocalityPolygon> _polygons;

  static Future<BogotaLocalityService> load() {
    return _instance ??= _load();
  }

  static Future<BogotaLocalityService> _load() async {
    final encoded = await rootBundle.loadString(
      'assets/geo/bogota_localities.geojson',
    );
    final collection = jsonDecode(encoded) as Map<String, dynamic>;
    final features = collection['features'] as List<dynamic>;
    final polygons = <_LocalityPolygon>[];

    for (final featureValue in features) {
      final feature = featureValue as Map<String, dynamic>;
      final properties = feature['properties'] as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List<dynamic>;
      final multipolygon = coordinates.map((polygonValue) {
        final rings = polygonValue as List<dynamic>;
        return rings.map((ringValue) {
          final positions = ringValue as List<dynamic>;
          return positions.map((positionValue) {
            final position = positionValue as List<dynamic>;
            return LatLng(
              (position[1] as num).toDouble(),
              (position[0] as num).toDouble(),
            );
          }).toList(growable: false);
        }).toList(growable: false);
      }).toList(growable: false);

      final name = properties['name'];
      if (name is! String || name.isEmpty) {
        throw const FormatException('Localidad sin nombre en el GeoJSON.');
      }
      polygons.add(_LocalityPolygon(name, multipolygon));
    }

    return BogotaLocalityService._(polygons);
  }

  String? localityAt(LatLng point) {
    for (final locality in _polygons) {
      for (final polygon in locality.polygons) {
        if (_isInsideRing(point, polygon.first) &&
            !polygon.skip(1).any((hole) => _isInsideRing(point, hole))) {
          return locality.name;
        }
      }
    }
    return null;
  }

  bool _isInsideRing(LatLng point, List<LatLng> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final current = ring[i];
      final previous = ring[j];

      if (_isOnSegment(point, previous, current)) return true;

      if ((current.latitude > point.latitude) !=
          (previous.latitude > point.latitude)) {
        final intersectionLongitude =
            (previous.longitude - current.longitude) *
                (point.latitude - current.latitude) /
                (previous.latitude - current.latitude) +
            current.longitude;
        if (point.longitude < intersectionLongitude) inside = !inside;
      }
    }
    return inside;
  }

  bool _isOnSegment(LatLng point, LatLng start, LatLng end) {
    const tolerance = 1e-10;
    final crossProduct =
        (point.latitude - start.latitude) *
            (end.longitude - start.longitude) -
        (point.longitude - start.longitude) *
            (end.latitude - start.latitude);
    if (crossProduct.abs() > tolerance) return false;

    return point.longitude >=
            (start.longitude < end.longitude
                ? start.longitude
                : end.longitude) -
                tolerance &&
        point.longitude <=
            (start.longitude > end.longitude
                ? start.longitude
                : end.longitude) +
                tolerance &&
        point.latitude >=
            (start.latitude < end.latitude ? start.latitude : end.latitude) -
                tolerance &&
        point.latitude <=
            (start.latitude > end.latitude ? start.latitude : end.latitude) +
                tolerance;
  }
}

class _LocalityPolygon {
  const _LocalityPolygon(this.name, this.polygons);

  final String name;
  final List<List<List<LatLng>>> polygons;
}
