import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'location_service.dart';

class DirectionsService {
  DirectionsService({LocationService? locationService})
    : _locationService = locationService ?? LocationService();

  final LocationService _locationService;

  Future<bool> openWalkingDirections({
    required double destinationLatitude,
    required double destinationLongitude,
  }) async {
    LatLng? origin;
    try {
      final position = await _locationService.getCurrentLocationOrNull();
      if (position != null) {
        origin = LatLng(position.latitude, position.longitude);
      }
    } catch (error) {
      debugPrint('No se pudo obtener el origen para la ruta: $error');
    }

    final destination = '$destinationLatitude,$destinationLongitude';
    final originValue = origin == null
        ? 'My Location'
        : '${origin.latitude},${origin.longitude}';
    final uris = [
      Uri.parse('google.navigation:q=$destination&mode=w'),
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'origin': originValue,
        'destination': destination,
        'travelmode': 'walking',
      }),
      Uri.parse('geo:$destination?q=$destination'),
    ];

    for (final uri in uris) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
        debugPrint('No se pudo abrir la aplicación de rutas para $uri');
      } catch (error) {
        debugPrint('Falló el intento de abrir $uri: $error');
      }
    }

    return false;
  }
}
