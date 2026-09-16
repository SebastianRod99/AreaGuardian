import 'package:geolocator/geolocator.dart';

class LocationService {
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