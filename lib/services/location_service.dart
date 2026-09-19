import 'package:geolocator/geolocator.dart';

class LocationService {
  static const double vendorProximityRadiusMeters = 50.0;

  double distanceBetween(Position position, double latitude, double longitude) {
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      latitude,
      longitude,
    );
  }

  bool isWithinVendorRadius(
    Position position,
    double latitude,
    double longitude,
  ) {
    return distanceBetween(position, latitude, longitude) <=
        vendorProximityRadiusMeters;
  }

  Future<Position?> getCurrentLocationOrNull() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Position?> getCurrentLocationForEmergency() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }

  // Obtener la ubicación actual del usuario
  Future<Position> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Verificar si el servicio de localización está activo
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return _getDefaultLocation();
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return _getDefaultLocation();
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return _getDefaultLocation();
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      // Si falla el GPS del emulador, retorna posición por defecto
      return _getDefaultLocation();
    }
  }

  // Ubicación de respaldo por defecto (Bogotá - Zona de prueba)
  Position _getDefaultLocation() {
    return Position(
      latitude: 4.6738,
      longitude: -74.1467,
      timestamp: DateTime.now(),
      accuracy: 1.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 0.0,
      headingAccuracy: 0.0,
    );
  }
}
