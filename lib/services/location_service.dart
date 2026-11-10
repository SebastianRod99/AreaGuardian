import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static const double vendorProximityRadiusMeters = 50.0;
  static const Duration vendorLocationUpdateInterval = Duration(seconds: 30);
  static const double vendorLocationUpdateDistanceMeters = 50.0;
  static const Duration _permissionCheckTimeout = Duration(seconds: 3);
  static const Duration _locationServiceTimeout = Duration(seconds: 3);
  static const Duration _lastKnownPositionTimeout = Duration(seconds: 3);
  static const Duration _currentPositionTimeout = Duration(seconds: 12);

  static Future<LocationPermission>? _locationPermissionRequest;
  static Future<Position?>? _currentPositionRequest;

  Timer? _vendorLocationTimer;
  Position? _lastVendorLocation;
  bool _vendorLocationUpdateInProgress = false;

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

  static Future<LocationPermission> ensureLocationPermission() {
    return _locationPermissionRequest ??= _requestLocationPermission();
  }

  static Future<LocationPermission> _requestLocationPermission() async {
    try {
      var permission = await Geolocator.checkPermission().timeout(
        _permissionCheckTimeout,
      );
      debugPrint('Location permission checked: $permission');
      if (permission == LocationPermission.denied) {
        debugPrint('Requesting location permission');
        permission = await Geolocator.requestPermission();
        debugPrint('Location permission result: $permission');
      }
      return permission;
    } catch (error) {
      debugPrint('Location permission request failed: $error');
      return LocationPermission.denied;
    }
  }

  Future<bool> _isLocationServiceEnabled() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled().timeout(
        _locationServiceTimeout,
      );
      if (!enabled) debugPrint('Location services are disabled');
      return enabled;
    } catch (error) {
      debugPrint('Could not check location services: $error');
      return false;
    }
  }

  Future<Position?> getLastKnownLocationOrNull() async {
    final permission = await ensureLocationPermission();
    if (!_hasLocationPermission(permission) ||
        !await _isLocationServiceEnabled()) {
      return null;
    }

    try {
      return await Geolocator.getLastKnownPosition().timeout(
        _lastKnownPositionTimeout,
      );
    } catch (error) {
      debugPrint('Could not read last known location: $error');
      return null;
    }
  }

  Future<Position?> getFreshLocationOrNull() async {
    final pendingRequest = _currentPositionRequest;
    if (pendingRequest != null) return pendingRequest;

    final request = _getFreshLocationOrNull();
    _currentPositionRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_currentPositionRequest, request)) {
        _currentPositionRequest = null;
      }
    }
  }

  Future<Position?> _getFreshLocationOrNull() async {
    final permission = await ensureLocationPermission();
    if (!_hasLocationPermission(permission) ||
        !await _isLocationServiceEnabled()) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _currentPositionTimeout,
        ),
      ).timeout(_currentPositionTimeout);
    } on TimeoutException {
      debugPrint(
        'Fresh location timed out after '
        '${_currentPositionTimeout.inSeconds}s',
      );
      return null;
    } catch (error) {
      debugPrint('Could not get a fresh location: $error');
      return null;
    }
  }

  bool _hasLocationPermission(LocationPermission permission) {
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<void> startVendorLocationUpdates({
    required Future<void> Function(Position position) onLocationUpdate,
  }) async {
    stopVendorLocationUpdates();
    await _updateVendorLocation(onLocationUpdate);
    _vendorLocationTimer = Timer.periodic(
      vendorLocationUpdateInterval,
      (_) => _updateVendorLocation(onLocationUpdate),
    );
  }

  void stopVendorLocationUpdates() {
    _vendorLocationTimer?.cancel();
    _vendorLocationTimer = null;
    _lastVendorLocation = null;
  }

  Future<void> _updateVendorLocation(
    Future<void> Function(Position position) onLocationUpdate,
  ) async {
    if (_vendorLocationUpdateInProgress) return;
    _vendorLocationUpdateInProgress = true;
    try {
      final position = await getCurrentLocationOrNull();
      if (position == null) return;
      if (_lastVendorLocation != null &&
          distanceBetween(
                position,
                _lastVendorLocation!.latitude,
                _lastVendorLocation!.longitude,
              ) <
              vendorLocationUpdateDistanceMeters) {
        return;
      }
      _lastVendorLocation = position;
      await onLocationUpdate(position);
    } catch (_) {
      // A temporary GPS failure must not stop future tracking attempts.
    } finally {
      _vendorLocationUpdateInProgress = false;
    }
  }

  Future<Position?> getCurrentLocationOrNull() async {
    final lastKnownPosition = await getLastKnownLocationOrNull();
    return await getFreshLocationOrNull() ?? lastKnownPosition;
  }

  Future<Position?> getCurrentLocationForEmergency() async {
    final permission = await ensureLocationPermission();
    if (!_hasLocationPermission(permission) ||
        !await _isLocationServiceEnabled()) {
      return null;
    }

    try {
      final lastKnownPosition = await Geolocator.getLastKnownPosition().timeout(
        _lastKnownPositionTimeout,
      );
      if (lastKnownPosition != null &&
          DateTime.now().difference(lastKnownPosition.timestamp) <=
              const Duration(minutes: 5)) {
        return lastKnownPosition;
      }
    } catch (error) {
      debugPrint('Could not read last known emergency location: $error');
    }

    return getFreshLocationOrNull();
  }
}
