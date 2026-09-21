import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// Importamos servicios, modelos y Firestore
import '../services/location_service.dart';
import '../services/firestore_service.dart';
import '../models/vendor_model.dart';
import '../models/emergency_model.dart';

// ==========================================
// PANTALLA DE MAPA — OpenStreetMap + Firestore
// ==========================================
class MapDashboardScreen extends StatefulWidget {
  /// Si vienen de una notificación de emergencia (HU-05), el mapa se centra
  /// aquí y se pinta un marcador de alerta en ese punto.
  final double? focusLatitude;
  final double? focusLongitude;

  const MapDashboardScreen({
    super.key,
    this.focusLatitude,
    this.focusLongitude,
  });

  @override
  State<MapDashboardScreen> createState() => _MapDashboardScreenState();
}

class _MapDashboardScreenState extends State<MapDashboardScreen> {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  final FirestoreService _firestoreService = FirestoreService();

  // Ubicación EN VIVO del usuario actual (dueño o cliente) — centra el mapa
  // y, si el rol es cliente, es también su propio marcador (HU-06).
  LatLng? _myLocation;
  // Ubicación FIJA de mi puesto — solo aplica a vendedores.
  LatLng? _myPuestoLocation;

  bool _isLoading = true;
  bool _locationDenied = false;
  bool _isVendorRole = false;

  String _myPuestoTitle = 'Mi Puesto';
  String _myAddress = '';
  String _vendorId = '';

  // Lista de puestos dinámicos obtenidos desde Firebase Firestore
  List<VendorModel> _puestosVecinos = [];
  List<EmergencyModel> _emergencies = [];
  StreamSubscription<List<EmergencyModel>>? _emergencySubscription;
  Timer? _emergencyExpiryTimer;
  VendorModel? _selectedVendorPuesto;
  bool _isMyPuestoSelected = false;

  @override
  void initState() {
    super.initState();
    _loadMyPuestoAndLocation();
    _emergencyExpiryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _removeExpiredEmergencies(),
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
  }

  void _watchActiveEmergencies() {
    _emergencySubscription?.cancel();
    _emergencySubscription = _firestoreService.watchActiveEmergencies().listen((
      emergencies,
    ) {
      if (mounted) setState(() => _emergencies = emergencies);
    });
  }

  Future<void> _loadMyPuestoAndLocation() async {
    // 1. Cargamos datos locales del usuario (rol + datos del puesto si aplica)
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isVendorRole = (prefs.getString('user_role') ?? '') == 'vendor';
      _vendorId = prefs.getString('vendor_id') ?? '';
      _myPuestoTitle = prefs.getString('puesto_title') ?? 'Mi Puesto';
      _myAddress = prefs.getString('vendor_address') ?? '';
    });

    // 2. Gestionamos permisos y obtenemos ubicación con nuestro LocationService
    final status = await Permission.location.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      setState(() {
        _locationDenied = true;
      });
      _watchActiveEmergencies();
    }

    try {
      Position position = await _locationService.getCurrentLocation();
      LatLng currentLatLng = LatLng(position.latitude, position.longitude);

      // Ubicación FIJA del puesto — solo tiene sentido para vendedores.
      // Un cliente nunca marcó 'vendor_latitude/longitude', así que su
      // marcador de "puesto" simplemente no se pinta (ver _buildMap).
      LatLng? fixedPuestoLatLng;
      if (_isVendorRole) {
        final double? fixedLat = prefs.getDouble('vendor_latitude');
        final double? fixedLng = prefs.getDouble('vendor_longitude');
        fixedPuestoLatLng = (fixedLat != null && fixedLng != null)
            ? LatLng(fixedLat, fixedLng)
            : currentLatLng; // fallback solo si nunca marcó su puesto
      }

      setState(() {
        _myPuestoLocation = fixedPuestoLatLng;
        _myLocation = currentLatLng;
      });

      // 3. Consultamos los puestos reales directamente desde Firestore
      List<VendorModel> vendors = await _firestoreService.fetchNearbyVendors();
      List<EmergencyModel> emergencies = await _firestoreService
          .fetchActiveEmergencies();

      setState(() {
        _puestosVecinos = vendors;
        _emergencies = emergencies;
        final myVendor = vendors
            .where((vendor) => vendor.id == _vendorId)
            .firstOrNull;
        if (myVendor != null) {
          _myPuestoTitle = myVendor.shopName.isNotEmpty
              ? myVendor.shopName
              : _myPuestoTitle;
          _myAddress = myVendor.address.isNotEmpty
              ? myVendor.address
              : _myAddress;
        }
        _isLoading = false;
      });
      _watchActiveEmergencies();

      // HU-05: si llegamos desde una notificación de emergencia, centramos
      // el mapa ahí en cuanto el widget termine de construirse.
      if (widget.focusLatitude != null && widget.focusLongitude != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.move(
            LatLng(widget.focusLatitude!, widget.focusLongitude!),
            18,
          );
        });
      }
    } catch (e) {
      // Coordenadas por defecto en caso de error (Bogotá)
      const fallbackLatLng = LatLng(4.6742, -74.1468);
      setState(() {
        _myLocation = fallbackLatLng;
        _myPuestoLocation = _isVendorRole ? fallbackLatLng : null;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _emergencySubscription?.cancel();
    _emergencyExpiryTimer?.cancel();
    super.dispose();
  }

  void _centerOnMe() {
    if (_myLocation != null) {
      _mapController.move(_myLocation!, 17);
    }
  }

  void _selectVecino(VendorModel puesto) {
    setState(() {
      _selectedVendorPuesto = puesto;
      _isMyPuestoSelected = false;
    });
  }

  Future<void> _openDirections(VendorModel puesto) async {
    final destination = '${puesto.latitude},${puesto.longitude}';
    final navigationUris = [
      Uri.parse('comgooglemaps://?daddr=$destination&directionsmode=driving'),
      Uri.parse('waze://?ll=$destination&navigate=yes'),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$destination',
      ),
    ];

    for (final uri in navigationUris) {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir Google Maps ni Waze.')),
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
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00E6A7),
                      ),
                    )
                  : Stack(
                      children: [
                        _buildMap(),
                        _buildLegend(),
                        _buildCenterButton(),
                        if (showingEmergency) _buildEmergencyBanner(),
                        if (_locationDenied && !showingEmergency)
                          _buildLocationWarning(),
                        if (_selectedVendorPuesto != null ||
                            _isMyPuestoSelected)
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mapa de Puestos',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'Fontibón • ${_puestosVecinos.length} puestos • $activosCount activos',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1D2030),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: const [
                Icon(Icons.location_city, color: Color(0xFF00E6A7), size: 14),
                SizedBox(width: 6),
                Text(
                  'Parque Central',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
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
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _myLocation ?? const LatLng(4.6742, -74.1468),
        initialZoom: 16.5,
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
                    color: const Color(0xFF00E6A7),
                    icon: Icons.storefront,
                    isMe: true,
                  ),
                ),
              ),

            // Marcador rojo de una emergencia activa.
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
            ..._puestosVecinos.map(
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

  Widget _buildMarkerWidget({
    required Color color,
    required IconData icon,
    bool isMe = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF00E6A7) : const Color(0xFF1D2030),
        shape: BoxShape.circle,
        border: Border.all(color: isMe ? Colors.white : color, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        icon,
        size: isMe ? 22 : 18,
        color: isMe ? Colors.black : color,
      ),
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
            _legendItem(
              const Color(0xFF00E6A7),
              _isVendorRole ? 'Mi puesto' : 'Yo',
            ),
            const SizedBox(height: 4),
            _legendItem(const Color(0xFF00E6A7), 'Activo'),
            const SizedBox(height: 4),
            _legendItem(Colors.grey, 'Inactivo'),
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
        child: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ubicación no disponible — mostrando Fontibón',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AVISO DE EMERGENCIA (HU-05) ───────────────────────────────────────────
  Widget _buildEmergencyBanner() {
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
        child: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '🚨 Emergencia cerca — ve al punto marcado en rojo',
                style: TextStyle(
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
                        ? const Color(0xFF00E6A7).withOpacity(0.12)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isMe
                          ? const Color(0xFF00E6A7).withOpacity(0.4)
                          : Colors.white12,
                    ),
                  ),
                  child: Icon(
                    isMe ? Icons.storefront : Icons.store_outlined,
                    size: 26,
                    color: isMe ? const Color(0xFF00E6A7) : Colors.white54,
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
