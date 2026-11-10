import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Importamos servicios, modelos y Firestore
import '../services/location_service.dart';
import '../services/directions_service.dart';
import '../services/bogota_locality_service.dart';
import '../services/firestore_service.dart';
import '../models/vendor_model.dart';
import '../models/emergency_model.dart';
import '../utils/constant.dart';
import '../utils/geo_utils.dart';

// ==========================================
// PANTALLA DE MAPA — OpenStreetMap + Firestore
// ==========================================
class MapDashboardScreen extends StatefulWidget {
  final bool isVisible;

  /// Si vienen de una notificación de emergencia (HU-05), el mapa se centra
  /// aquí y se pinta un marcador de alerta en ese punto.
  final double? focusLatitude;
  final double? focusLongitude;
  final String? focusSourceLabel;

  const MapDashboardScreen({
    super.key,
    this.isVisible = true,
    this.focusLatitude,
    this.focusLongitude,
    this.focusSourceLabel,
  });

  @override
  State<MapDashboardScreen> createState() => _MapDashboardScreenState();
}

class _MapDashboardScreenState extends State<MapDashboardScreen> {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  final DirectionsService _directionsService = DirectionsService();
  final FirestoreService _firestoreService = FirestoreService();
  final AudioPlayer _emergencyPlayer = AudioPlayer();
  final Geocoding _geocoding = Geocoding();
  StreamSubscription<Position>? _userPositionSubscription;
  StreamSubscription<User?>? _authSubscription;

  // Ubicación EN VIVO del usuario actual (dueño o cliente) — centra el mapa
  // y, si el rol es cliente, es también su propio marcador (HU-06).
  LatLng? _myLocation;
  // Ubicación FIJA de mi puesto — solo aplica a vendedores.
  LatLng? _myPuestoLocation;
  LatLng? _lastGeocodedLocation;
  LatLng? _pendingGeocodedLocation;
  bool _isGeocodingLocation = false;

  bool _locationPermissionPending = true;
  bool _locationDenied = false;
  bool _mapReady = false;
  bool _hasCenteredOnGps = false;
  LatLng? _pendingMapCenter;
  bool _isVendorRole = false;
  bool _isEmergencyAlarmMuted = false;
  bool _isEmergencyAlarmPlaying = false;

  String _myPuestoTitle = 'Mi Puesto';
  String _myAddress = '';
  String? _neighborhood;
  String _locality = 'Bogotá';
  String _vendorId = '';
  String _userId = '';
  LatLng? _emergencyQueryCenter;
  LatLng? _emergencyPendingCenter;
  int _emergencyQueryGeneration = 0;
  int _emergencyRetryAttempt = 0;
  bool _showEmergencyQueryWarning = false;
  Timer? _emergencyRetryTimer;

  static const List<Duration> _emergencyRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
  ];

  // Lista de puestos dinámicos obtenidos desde Firebase Firestore
  List<VendorModel> _puestosVecinos = [];
  List<EmergencyModel> _emergencies = [];
  StreamSubscription<List<VendorModel>>? _vendorSubscription;
  StreamSubscription<ActiveEmergenciesSnapshot>? _emergencySubscription;
  Timer? _emergencyExpiryTimer;
  VendorModel? _selectedVendorPuesto;
  bool _isMyPuestoSelected = false;

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleAuthState,
      onError: (Object error) {
        _logEmergencyQueryError('esperar la sesión autenticada', error);
      },
    );
    _loadMyPuestoAndLocation();
    _emergencyExpiryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _removeExpiredEmergencies(),
    );
  }

  void _handleAuthState(User? user) {
    if (!mounted) return;
    final nextUserId = user?.uid ?? '';
    if (_userId == nextUserId) return;

    _userId = nextUserId;
    _emergencyQueryGeneration++;
    _emergencyRetryTimer?.cancel();
    _emergencySubscription?.cancel();
    _emergencySubscription = null;
    _emergencyPendingCenter = null;
    _emergencyQueryCenter = null;
    _emergencyRetryAttempt = 0;
    if (nextUserId.isEmpty) {
      setState(() {
        _emergencies = [];
        _showEmergencyQueryWarning = false;
      });
      unawaited(_stopEmergencyAlarm());
      return;
    }

    final location = _emergencyMonitoringLocation;
    if (location != null) {
      _requestEmergencyRefresh(location);
    }
  }

  LatLng? get _emergencyMonitoringLocation {
    final location = _myLocation ?? (_isVendorRole ? _myPuestoLocation : null);
    if (location == null ||
        !location.latitude.isFinite ||
        !location.longitude.isFinite ||
        (location.latitude == 0 && location.longitude == 0) ||
        location.latitude < -90 ||
        location.latitude > 90 ||
        location.longitude < -180 ||
        location.longitude > 180) {
      return null;
    }
    return location;
  }

  void _logEmergencyQueryError(String operation, Object error) {
    final code = error is FirebaseException ? error.code : 'n/a';
    debugPrint(
      'Emergency $operation failed: '
      'type=${error.runtimeType}, code=$code, error=$error',
    );
  }

  void _removeExpiredEmergencies() {
    final cutoff = DateTime.now().subtract(
      FirestoreService.emergencyVisibilityDuration,
    );
    if (!mounted) return;
    setState(() {
      _emergencies = _emergencies
          .where((emergency) => emergency.timestamp.isAfter(cutoff))
          .toList();
    });
    _syncEmergencyAlarm();
  }

  bool _isOwnEmergency(EmergencyModel emergency) {
    return emergency.userId == _userId ||
        (_vendorId.isNotEmpty && emergency.userId == _vendorId);
  }

  Future<void> _playEmergencyAlarm() async {
    if (_isEmergencyAlarmPlaying || _isEmergencyAlarmMuted) return;
    try {
      await _emergencyPlayer.setAsset('assets/audio/alarm.mp3');
      await _emergencyPlayer.setLoopMode(LoopMode.all);
      await _emergencyPlayer.play();
      _isEmergencyAlarmPlaying = true;
    } catch (error) {
      debugPrint('No se pudo reproducir la alarma de emergencia: $error');
    }
  }

  Future<void> _stopEmergencyAlarm() async {
    if (!_isEmergencyAlarmPlaying && !_emergencyPlayer.playing) return;
    _isEmergencyAlarmPlaying = false;
    try {
      await _emergencyPlayer.stop();
    } catch (error) {
      debugPrint('No se pudo detener la alarma de emergencia: $error');
    }
  }

  void _syncEmergencyAlarm() {
    final myVendor = _puestosVecinos
        .where((vendor) => vendor.id == _vendorId)
        .firstOrNull;
    final location = _emergencyMonitoringLocation;
    if (_isEmergencyAlarmMuted ||
        !_isVendorRole ||
        myVendor?.isActive != true ||
        location == null) {
      unawaited(_stopEmergencyAlarm());
      return;
    }

    final hasNearbyEmergency = _emergencies.any(
      (emergency) =>
          !_isOwnEmergency(emergency) &&
          isWithinRadiusMeters(
            latitudeA: location.latitude,
            longitudeA: location.longitude,
            latitudeB: emergency.latitude,
            longitudeB: emergency.longitude,
            radiusMeters: FirestoreService.emergencyAlertRadiusMeters,
          ),
    );
    if (hasNearbyEmergency) {
      unawaited(_playEmergencyAlarm());
    } else {
      unawaited(_stopEmergencyAlarm());
    }
  }

  List<EmergencyModel> _filterEmergenciesAtCurrentLocation(
    List<EmergencyModel> emergencies,
  ) {
    final location = _emergencyMonitoringLocation;
    if (location == null) return [];
    return emergencies
        .where(
          (emergency) => isWithinRadiusMeters(
            latitudeA: location.latitude,
            longitudeA: location.longitude,
            latitudeB: emergency.latitude,
            longitudeB: emergency.longitude,
            radiusMeters: FirestoreService.emergencyAlertRadiusMeters,
          ),
        )
        .toList();
  }

  Future<void> _toggleEmergencyAlarmMute() async {
    final nextMuted = !_isEmergencyAlarmMuted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('map_emergency_alarm_muted', nextMuted);
    if (!mounted) return;
    setState(() => _isEmergencyAlarmMuted = nextMuted);
    _syncEmergencyAlarm();
  }

  void _watchPublicVendors() {
    _vendorSubscription?.cancel();
    _vendorSubscription = _firestoreService.watchPublicVendors().listen((
      vendors,
    ) {
      if (!mounted) return;

      final myVendor = vendors
          .where((vendor) => vendor.id == _vendorId)
          .firstOrNull;
      setState(() {
        _puestosVecinos = vendors;
        if (_selectedVendorPuesto != null) {
          _selectedVendorPuesto = vendors
              .where((vendor) => vendor.id == _selectedVendorPuesto!.id)
              .firstOrNull;
        }
        if (myVendor != null) {
          _myPuestoTitle = myVendor.shopName.isNotEmpty
              ? myVendor.shopName
              : _myPuestoTitle;
          _myAddress = myVendor.address.isNotEmpty
              ? myVendor.address
              : _myAddress;
          if (_isVendorRole &&
              myVendor.latitude != 0 &&
              myVendor.longitude != 0) {
            _myPuestoLocation = LatLng(myVendor.latitude, myVendor.longitude);
          }
        }
      });
      _syncEmergencyAlarm();
    });
  }

  Future<void> _loadMyPuestoAndLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _isVendorRole = (prefs.getString('user_role') ?? '') == 'vendor';
        _vendorId = prefs.getString('vendor_id') ?? '';
        _myPuestoTitle = prefs.getString('puesto_title') ?? 'Mi Puesto';
        _myAddress = prefs.getString('vendor_address') ?? '';
        _isEmergencyAlarmMuted =
            prefs.getBool('map_emergency_alarm_muted') ?? false;
      });
      _watchPublicVendors();

      final fixedLatitude = prefs.getDouble('vendor_latitude');
      final fixedLongitude = prefs.getDouble('vendor_longitude');
      LatLng? fixedPuestoLatLng;
      if (_isVendorRole && fixedLatitude != null && fixedLongitude != null) {
        fixedPuestoLatLng = LatLng(fixedLatitude, fixedLongitude);
      }
      setState(() {
        _myPuestoLocation = fixedPuestoLatLng;
      });
      final monitoringLocation = _emergencyMonitoringLocation;
      if (_userId.isNotEmpty && monitoringLocation != null) {
        _requestEmergencyRefresh(monitoringLocation);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadLocation());
      });
    } catch (error) {
      debugPrint('No se pudieron cargar los datos locales del mapa: $error');
      if (mounted) {
        setState(() {
          _locationPermissionPending = false;
          _locationDenied = true;
        });
      }
    }
  }

  Future<void> _loadLocation() async {
    final permission = await LocationService.ensureLocationPermission();
    if (!mounted) return;

    final hasPermission =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    setState(() {
      _locationPermissionPending = false;
      _locationDenied = !hasPermission;
    });
    debugPrint('Map location permission resolved: $permission');
    if (!hasPermission) {
      final fallbackLocation = _emergencyMonitoringLocation;
      if (_userId.isNotEmpty && fallbackLocation != null) {
        _requestEmergencyRefresh(fallbackLocation);
      }
      return;
    }

    _watchUserLocation();
    final lastKnownPosition = await _locationService
        .getLastKnownLocationOrNull();
    if (!mounted) return;
    if (lastKnownPosition != null) {
      debugPrint('Map received last known location');
      _applyLocation(lastKnownPosition);
    }
    unawaited(_loadFreshLocation());
  }

  Future<void> _loadFreshLocation() async {
    final position = await _locationService.getFreshLocationOrNull();
    if (!mounted) return;
    if (position == null) {
      if (_myLocation == null) setState(() => _locationDenied = true);
      return;
    }
    debugPrint('Map received fresh location');
    _applyLocation(position);
  }

  void _applyLocation(Position position) {
    final location = LatLng(position.latitude, position.longitude);
    setState(() {
      _myLocation = location;
      _locationDenied = false;
    });
    _centerMapOnLocation(location);
    _syncEmergencyAlarm();
    unawaited(_updateLocationNames(location));
    _requestEmergencyRefresh(location);
  }

  void _centerMapOnLocation(LatLng location) {
    if (widget.focusLatitude != null && widget.focusLongitude != null) {
      return;
    }
    _hasCenteredOnGps = true;
    if (!_mapReady) {
      _pendingMapCenter = location;
      return;
    }
    _mapController.move(location, 17);
  }

  void _requestEmergencyRefresh(LatLng location) {
    if (_userId.isEmpty) return;

    final previousCenter = _emergencyPendingCenter ?? _emergencyQueryCenter;
    if (previousCenter != null &&
        Geolocator.distanceBetween(
              previousCenter.latitude,
              previousCenter.longitude,
              location.latitude,
              location.longitude,
            ) <
            150) {
      return;
    }

    final generation = ++_emergencyQueryGeneration;
    _emergencyRetryTimer?.cancel();
    _emergencySubscription?.cancel();
    _emergencySubscription = null;
    _emergencyPendingCenter = location;
    _emergencyRetryAttempt = 0;
    unawaited(_runEmergencyQuery(location, generation));
  }

  Future<void> _runEmergencyQuery(LatLng location, int generation) async {
    if (!mounted ||
        generation != _emergencyQueryGeneration ||
        _userId.isEmpty ||
        FirebaseAuth.instance.currentUser?.uid != _userId) {
      return;
    }

    if (!await _updateEmergencyQueryLocation(location, generation)) return;
    if (!mounted ||
        generation != _emergencyQueryGeneration ||
        FirebaseAuth.instance.currentUser?.uid != _userId) {
      return;
    }

    unawaited(_emergencySubscription?.cancel());
    _emergencySubscription = null;
    _emergencyQueryCenter = location;
    _emergencyPendingCenter = null;
    try {
      _emergencySubscription = _firestoreService
          .watchActiveEmergencies(
            latitude: location.latitude,
            longitude: location.longitude,
          )
          .listen(
            (snapshot) {
              if (!mounted || generation != _emergencyQueryGeneration) return;
              if (!snapshot.isFromCache) {
                _emergencyRetryAttempt = 0;
                _emergencyRetryTimer?.cancel();
              }
              setState(() {
                _emergencies = _filterEmergenciesAtCurrentLocation(
                  snapshot.emergencies,
                );
                if (!snapshot.isFromCache) {
                  _showEmergencyQueryWarning = false;
                }
              });
              _syncEmergencyAlarm();
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!mounted || generation != _emergencyQueryGeneration) return;
              _logEmergencyQueryError('watchActiveEmergencies', error);
              unawaited(_emergencySubscription?.cancel());
              _emergencySubscription = null;
              _scheduleEmergencyQueryRetry(location, generation);
            },
          );
    } catch (error) {
      if (!mounted || generation != _emergencyQueryGeneration) return;
      _logEmergencyQueryError('watchActiveEmergencies', error);
      _scheduleEmergencyQueryRetry(location, generation);
      return;
    }
  }

  Future<bool> _updateEmergencyQueryLocation(
    LatLng location,
    int generation,
  ) async {
    if (!mounted ||
        generation != _emergencyQueryGeneration ||
        FirebaseAuth.instance.currentUser?.uid != _userId) {
      return false;
    }

    try {
      await _firestoreService.updateUserCurrentLocation(
        latitude: location.latitude,
        longitude: location.longitude,
      );
      return true;
    } catch (error) {
      if (!mounted || generation != _emergencyQueryGeneration) return false;
      _logEmergencyQueryError('actualizar ubicación para alertas', error);
      _scheduleEmergencyQueryRetry(location, generation);
      return false;
    }
  }

  void _scheduleEmergencyQueryRetry(LatLng location, int generation) {
    if (_emergencyRetryTimer?.isActive == true) return;

    if (_emergencyRetryAttempt < _emergencyRetryDelays.length) {
      final delay = _emergencyRetryDelays[_emergencyRetryAttempt++];
      _emergencyRetryTimer?.cancel();
      _emergencyRetryTimer = Timer(delay, () {
        _emergencyRetryTimer = null;
        unawaited(_runEmergencyQuery(location, generation));
      });
      return;
    }

    if (!_showEmergencyQueryWarning) {
      setState(() => _showEmergencyQueryWarning = true);
    }
    _emergencyRetryTimer?.cancel();
    _emergencyRetryTimer = Timer(_emergencyRetryDelays.last, () {
      _emergencyRetryTimer = null;
      unawaited(_runEmergencyQuery(location, generation));
    });
  }

  void _watchUserLocation() {
    _userPositionSubscription?.cancel();
    _userPositionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(distanceFilter: 25),
        ).listen(
          (position) {
            if (!mounted) return;
            final location = LatLng(position.latitude, position.longitude);
            setState(() {
              _myLocation = location;
              _emergencies = _filterEmergenciesAtCurrentLocation(_emergencies);
              _locationDenied = false;
            });
            if (!_hasCenteredOnGps) _centerMapOnLocation(location);
            _syncEmergencyAlarm();
            unawaited(_updateLocationNames(location));
            final queryCenter = _emergencyQueryCenter;
            if (_userId.isNotEmpty &&
                (queryCenter == null ||
                    Geolocator.distanceBetween(
                          queryCenter.latitude,
                          queryCenter.longitude,
                          location.latitude,
                          location.longitude,
                        ) >=
                        150)) {
              _requestEmergencyRefresh(location);
            }
          },
          onError: (Object error) {
            debugPrint('No se pudo actualizar la ubicación del mapa: $error');
            if (mounted && _myLocation == null) {
              setState(() => _locationDenied = true);
            }
          },
        );
  }

  Future<void> _updateLocationNames(LatLng location) async {
    if (_isGeocodingLocation) {
      _pendingGeocodedLocation = location;
      return;
    }
    final previousLocation = _lastGeocodedLocation;
    if (previousLocation != null &&
        Geolocator.distanceBetween(
              previousLocation.latitude,
              previousLocation.longitude,
              location.latitude,
              location.longitude,
            ) <
            150) {
      return;
    }
    _lastGeocodedLocation = location;
    _isGeocodingLocation = true;
    var locality = 'Bogotá';
    try {
      final localityService = await BogotaLocalityService.load();
      locality = localityService.localityAt(location) ?? 'Fuera de Bogotá';
    } catch (error) {
      debugPrint('No se pudo cargar la geometría de localidades: $error');
    }

    String? neighborhood;
    try {
      final placemarks = await _geocoding.placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      final placemark = placemarks.firstOrNull;
      neighborhood = _firstNonEmpty([placemark?.subLocality]);
    } catch (error) {
      debugPrint('No se pudo identificar el barrio: $error');
    } finally {
      _isGeocodingLocation = false;
      final pendingLocation = _pendingGeocodedLocation;
      _pendingGeocodedLocation = null;
      if (pendingLocation != null &&
          Geolocator.distanceBetween(
                location.latitude,
                location.longitude,
                pendingLocation.latitude,
                pendingLocation.longitude,
              ) >=
              150) {
        unawaited(_updateLocationNames(pendingLocation));
      }
    }

    if (!mounted) return;
    setState(() {
      _neighborhood = neighborhood;
      _locality = locality;
    });
  }

  String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmedValue = value?.trim();
      if (trimmedValue != null && trimmedValue.isNotEmpty) return trimmedValue;
    }
    return null;
  }

  @override
  void dispose() {
    _userPositionSubscription?.cancel();
    _authSubscription?.cancel();
    _vendorSubscription?.cancel();
    _emergencySubscription?.cancel();
    _emergencyRetryTimer?.cancel();
    _emergencyExpiryTimer?.cancel();
    _emergencyPlayer.dispose();
    super.dispose();
  }

  void _centerOnMe() {
    if (_myLocation != null) {
      _mapController.move(_myLocation!, 17);
    }
  }

  Widget _buildEmergencyQueryWarning() {
    return Material(
      color: const Color(0xFF2B2630),
      borderRadius: BorderRadius.circular(10),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.cloud_off, size: 17, color: Colors.white70),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No se pudieron cargar las alertas cercanas. Reintentando...',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectVecino(VendorModel puesto) {
    setState(() {
      _selectedVendorPuesto = puesto;
      _isMyPuestoSelected = false;
    });
  }

  Future<void> _openDirections(VendorModel puesto) async {
    final opened = await _directionsService.openWalkingDirections(
      destinationLatitude: puesto.latitude,
      destinationLongitude: puesto.longitude,
    );
    if (mounted && !opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir una aplicación de rutas.'),
        ),
      );
    }
  }

  void _showVendorProfile(VendorModel puesto) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VendorProfileSheet(puesto: puesto),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activosCount = _puestosVecinos.where((p) => p.isActive).length;
    final bool showingEmergency =
        widget.focusLatitude != null && widget.focusLongitude != null;

    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(activosCount),
            Expanded(
              child: Stack(
                children: [
                  _buildMap(),
                  _buildLegend(),
                  _buildCenterButton(),
                  if (showingEmergency || _emergencies.isNotEmpty)
                    _buildEmergencyBanner(),
                  if (widget.isVisible && _showEmergencyQueryWarning)
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: _buildEmergencyQueryWarning(),
                    ),
                  if ((_locationDenied || _locationPermissionPending) &&
                      !showingEmergency)
                    _buildLocationWarning(),
                  if (_selectedVendorPuesto != null || _isMyPuestoSelected)
                    _buildPuestoCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────
  Widget _buildHeader(int activosCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      color: const Color(0xFF121420),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mapa de Puestos',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '$_locality • ${_puestosVecinos.length} puestos • $activosCount activos',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_neighborhood != null)
            Container(
              constraints: const BoxConstraints(maxWidth: 130),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1D2030),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_city,
                    color: Color(0xFF00E6A7),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _neighborhood!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (_isVendorRole)
                    IconButton(
                      tooltip: _isEmergencyAlarmMuted
                          ? 'Activar sonido de alarmas'
                          : 'Silenciar alarmas',
                      onPressed: _toggleEmergencyAlarmMute,
                      icon: Icon(
                        _isEmergencyAlarmMuted
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_active_outlined,
                        color: _isEmergencyAlarmMuted
                            ? Colors.white54
                            : const Color(0xFFFFB300),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── MAPA (FlutterMap / OpenStreetMap) ─────────────────────────────────────
  Widget _buildMap() {
    final focusCenter =
        widget.focusLatitude != null && widget.focusLongitude != null
        ? LatLng(widget.focusLatitude!, widget.focusLongitude!)
        : null;
    final initialCenter = focusCenter ?? _myLocation ?? _myPuestoLocation;
    if (initialCenter == null) {
      return Center(
        child: Icon(
          _locationPermissionPending
              ? Icons.location_searching
              : Icons.location_off,
          color: Colors.white54,
          size: 36,
        ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 16.5,
        onMapReady: () {
          _mapReady = true;
          if (widget.focusLatitude != null && widget.focusLongitude != null) {
            _mapController.move(
              LatLng(widget.focusLatitude!, widget.focusLongitude!),
              18,
            );
          } else if (_pendingMapCenter != null) {
            _mapController.move(_pendingMapCenter!, 17);
            _pendingMapCenter = null;
          }
        },
        onTap: (_, __) => setState(() {
          _selectedVendorPuesto = null;
          _isMyPuestoSelected = false;
        }),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.areaguardian.app',
        ),
        MarkerLayer(
          markers: [
            // Mi puesto — ubicación FIJA (pick_location_map), ícono tienda.
            // Solo aplica al rol vendedor.
            if (_isVendorRole && _myPuestoLocation != null)
              Marker(
                point: _myPuestoLocation!,
                width: 44,
                height: 44,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _isMyPuestoSelected = true;
                    _selectedVendorPuesto = null;
                  }),
                  child: _buildMarkerWidget(
                    color: myVendorColor,
                    icon: Icons.storefront,
                  ),
                ),
              ),

            // Marcador rojo de una emergencia activa.
            if (_myLocation != null)
              Marker(
                point: _myLocation!,
                width: 40,
                height: 40,
                child: _buildMarkerWidget(
                  color: const Color(0xFF448AFF),
                  icon: Icons.person_pin_circle,
                ),
              ),

            ..._emergencies.map(
              (emergency) => Marker(
                point: LatLng(emergency.latitude, emergency.longitude),
                width: 54,
                height: 54,
                child: _buildEmergencyMarker(),
              ),
            ),
            if (widget.focusLatitude != null && widget.focusLongitude != null)
              Marker(
                point: LatLng(widget.focusLatitude!, widget.focusLongitude!),
                width: 46,
                height: 46,
                child: _buildMarkerWidget(
                  color: Colors.red,
                  icon: Icons.warning_amber_rounded,
                ),
              ),

            // Puestos de la red: únicamente su ubicación comercial fija.
            ..._puestosVecinos
                .where((puesto) => puesto.id != _vendorId)
                .map(
                  (puesto) => Marker(
                    point: LatLng(puesto.latitude, puesto.longitude),
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => _selectVecino(puesto),
                      child: _buildMarkerWidget(
                        icon: Icons.store_outlined,
                        color: puesto.isActive
                            ? const Color(0xFF00E6A7)
                            : Colors.grey,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmergencyMarker() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.22),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.red, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.redAccent, blurRadius: 12, spreadRadius: 2),
        ],
      ),
      child: const Icon(
        Icons.warning_amber_rounded,
        color: Colors.red,
        size: 28,
      ),
    );
  }

  Widget _buildMarkerWidget({required Color color, required IconData icon}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1D2030),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  // ── LEYENDA ───────────────────────────────────────────────────────────────
  Widget _buildLegend() {
    return Positioned(
      top: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1D2030).withOpacity(0.95),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _legendItem(myVendorColor, 'Mi puesto'),
            const SizedBox(height: 4),
            _legendItem(const Color(0xFF448AFF), 'Yo'),
            const SizedBox(height: 4),
            _legendItem(const Color(0xFF00E6A7), 'Puesto activo'),
            const SizedBox(height: 4),
            _legendItem(Colors.grey, 'Inactivo'),
            const SizedBox(height: 4),
            _legendItem(Colors.red, 'Emergencia'),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }

  // ── BOTÓN CENTRAR ─────────────────────────────────────────────────────────
  Widget _buildCenterButton() {
    bool cardOpen = (_selectedVendorPuesto != null || _isMyPuestoSelected);
    return Positioned(
      bottom: cardOpen ? 240 : 20,
      right: 12,
      child: GestureDetector(
        onTap: _centerOnMe,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF1D2030),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6),
            ],
          ),
          child: const Icon(
            Icons.my_location,
            color: Color(0xFF00E6A7),
            size: 20,
          ),
        ),
      ),
    );
  }

  // ── AVISO UBICACIÓN DENEGADA ──────────────────────────────────────────────
  Widget _buildLocationWarning() {
    final message = _locationPermissionPending
        ? 'Esperando permiso de ubicación'
        : 'Ubicación no disponible';
    return Positioned(
      top: 12,
      left: 12,
      right: 70,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              _locationPermissionPending
                  ? Icons.location_searching
                  : Icons.location_off,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AVISO DE EMERGENCIA (HU-05) ───────────────────────────────────────────
  Widget _buildEmergencyBanner() {
    final activeEmergency = _emergencies.firstOrNull;
    final sourceLabel =
        widget.focusSourceLabel ??
        (activeEmergency?.role == 'vendor' &&
                activeEmergency!.shopName.trim().isNotEmpty
            ? activeEmergency.shopName
            : 'un vecino en la vía pública');

    return Positioned(
      top: 12,
      left: 12,
      right: 70,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.92),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '🚨 Alerta en $sourceLabel — ve al punto marcado en rojo',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── TARJETA DE PUESTO SELECCIONADO ────────────────────────────────────────
  Widget _buildPuestoCard() {
    final isMe = _isMyPuestoSelected;
    final puesto = _selectedVendorPuesto;

    final title = isMe
        ? _myPuestoTitle
        : (puesto?.shopName ?? 'Puesto Comercial');
    final address = isMe
        ? (_myAddress.isNotEmpty ? _myAddress : 'Sin dirección registrada')
        : (puesto?.address.isNotEmpty == true
              ? puesto!.address
              : 'Dirección no registrada');
    final isActive = isMe || (puesto?.isActive ?? false);

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Color(0xFF1D2030),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isMe
                        ? myVendorColor.withOpacity(0.12)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isMe
                          ? myVendorColor.withOpacity(0.4)
                          : Colors.white12,
                    ),
                  ),
                  child: Icon(
                    isMe ? Icons.storefront : Icons.store_outlined,
                    size: 26,
                    color: isMe ? myVendorColor : Colors.white54,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(isActive),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 12,
                            color: Colors.white38,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              address,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!isMe && puesto != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openDirections(puesto),
                      icon: const Icon(Icons.directions, size: 18),
                      label: const Text('Cómo llegar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showVendorProfile(puesto),
                      icon: const Icon(Icons.storefront, size: 18),
                      label: const Text('Ver perfil'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E6A7),
                        foregroundColor: Colors.black,
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isActive) {
    final color = isActive ? const Color(0xFF00E6A7) : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isActive ? 'Activo' : 'Inactivo',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _VendorProfileSheet extends StatelessWidget {
  final VendorModel puesto;

  const _VendorProfileSheet({required this.puesto});

  @override
  Widget build(BuildContext context) {
    final paymentMethods = <String>[
      if (puesto.nequiNumber.trim().isNotEmpty)
        'Nequi: ${puesto.nequiNumber.trim()}',
      if (puesto.daviplataNumber.trim().isNotEmpty)
        'Daviplata: ${puesto.daviplataNumber.trim()}',
    ];

    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 620),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Color(0xFF1D2030),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                puesto.shopName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                puesto.address.isEmpty
                    ? 'Dirección no registrada'
                    : puesto.address,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 22),
              const Text(
                'Catálogo / menú',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (puesto.catalog.isEmpty)
                const Text(
                  'El negocio aún no ha publicado productos.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                )
              else
                ...puesto.catalog.map(
                  (item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF00E6A7),
                      size: 18,
                    ),
                    title: Text(
                      item,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'Pagos digitales',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (paymentMethods.isEmpty)
                const Text(
                  'No hay medios de pago publicados.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                )
              else
                ...paymentMethods.map(
                  (method) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      method,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
