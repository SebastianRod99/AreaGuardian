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

// ==========================================
// PANTALLA DE MAPA — OpenStreetMap + Firestore
// ==========================================
class MapDashboardScreen extends StatefulWidget {
  const MapDashboardScreen({super.key});

  @override
  State<MapDashboardScreen> createState() => _MapDashboardScreenState();
}

class _MapDashboardScreenState extends State<MapDashboardScreen> {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  final FirestoreService _firestoreService = FirestoreService();

  LatLng? _myLocation;
  LatLng? _myPuestoLocation;
  bool _isLoading = true;
  bool _locationDenied = false;

  String _myPuestoTitle = 'Mi Puesto';
  String _myVendorName = '';
  String _myAddress = '';

  // Lista de puestos dinámicos obtenidos desde Firebase Firestore
  List<VendorModel> _puestosVecinos = [];
  VendorModel? _selectedVendorPuesto;
  bool _isMyPuestoSelected = false;

  @override
  void initState() {
    super.initState();
    _loadMyPuestoAndLocation();
  }

  Future<void> _loadMyPuestoAndLocation() async {
    // 1. Cargamos datos locales del puesto del usuario
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myPuestoTitle = prefs.getString('puesto_title') ?? 'Mi Puesto';
      _myVendorName = prefs.getString('vendor_name') ?? '';
      _myAddress = prefs.getString('vendor_address') ?? '';
    });

    // 2. Gestionamos permisos y obtenemos ubicación con nuestro LocationService
    final status = await Permission.location.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      setState(() {
        _locationDenied = true;
      });
    }

    try {
      Position position = await _locationService.getCurrentLocation();
      LatLng currentLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _myLocation = currentLatLng;
        _myPuestoLocation = currentLatLng;
      });

      // 3. Consultamos los puestos reales directamente desde Firestore
      List<VendorModel> vendors = await _firestoreService.fetchNearbyVendors();

      setState(() {
        _puestosVecinos = vendors;
        _isLoading = false;
      });
    } catch (e) {
      // Coordenadas por defecto en caso de error (Bogotá)
      const fallbackLatLng = LatLng(4.6742, -74.1468);
      setState(() {
        _myLocation = fallbackLatLng;
        _myPuestoLocation = fallbackLatLng;
        _isLoading = false;
      });
    }
  }

  void _centerOnMe() {
    if (_myLocation != null) {
      _mapController.move(_myLocation!, 17);
    }
  }

  Future<void> _navigateTo(VendorModel puesto) async {
    final lat = puesto.latitude;
    final lng = puesto.longitude;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activosCount = _puestosVecinos.where((p) => p.isActive).length;

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
                    color: Color(0xFF00E6A7)),
              )
                  : Stack(
                children: [
                  _buildMap(),
                  _buildLegend(),
                  _buildCenterButton(),
                  if (_locationDenied) _buildLocationWarning(),
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
                Icon(Icons.location_city,
                    color: Color(0xFF00E6A7), size: 14),
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
            // Mi puesto
            if (_myPuestoLocation != null)
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

            // Puestos de la red (Firestore)
            ..._puestosVecinos.map(
                  (puesto) => Marker(
                point: LatLng(puesto.latitude, puesto.longitude),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedVendorPuesto = puesto;
                    _isMyPuestoSelected = false;
                  }),
                  child: _buildMarkerWidget(
                    color: puesto.isActive ? Colors.white : Colors.white24,
                    icon: Icons.store_outlined,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
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
            _legendItem(const Color(0xFF00E6A7), 'Mi puesto'),
            const SizedBox(height: 4),
            _legendItem(Colors.white, 'Activo'),
            const SizedBox(height: 4),
            _legendItem(Colors.white24, 'Inactivo'),
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
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 11)),
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
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 6,
              ),
            ],
          ),
          child: const Icon(Icons.my_location,
              color: Color(0xFF00E6A7), size: 20),
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

  // ── TARJETA DE PUESTO SELECCIONADO ────────────────────────────────────────
  Widget _buildPuestoCard() {
    final isMe = _isMyPuestoSelected;
    final puesto = _selectedVendorPuesto;

    String title = isMe ? _myPuestoTitle : (puesto?.shopName ?? 'Puesto Comercial');
    String subtitle = isMe ? _myVendorName : (puesto?.category ?? '');
    String address = isMe ? (_myAddress.isNotEmpty ? _myAddress : 'Sin dirección registrada') : 'Nequi: ${puesto?.nequiNumber ?? "N/A"}';
    bool isActive = isMe ? true : (puesto?.isActive ?? false);

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
                    color: isMe
                        ? const Color(0xFF00E6A7)
                        : Colors.white54,
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
                          _buildBadge(isMe, isActive),
                        ],
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 12, color: Colors.white38),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              address,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12),
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
            const SizedBox(height: 16),

            // Botones según sea tu puesto o el de un vecino
            if (!isMe && puesto != null)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        _mapController.move(LatLng(puesto.latitude, puesto.longitude), 18);
                        setState(() {
                          _selectedVendorPuesto = null;
                        });
                      },
                      icon: const Icon(Icons.center_focus_strong,
                          color: Colors.white60, size: 18),
                      label: const Text('Ver en mapa',
                          style: TextStyle(
                              color: Colors.white60, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E6A7),
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => _navigateTo(puesto),
                      icon: const Icon(Icons.directions_walk, size: 18),
                      label: const Text('Navegar',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),

            if (isMe)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: const Color(0xFF00E6A7).withOpacity(0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => setState(() {
                    _isMyPuestoSelected = false;
                  }),
                  icon: const Icon(Icons.check_circle_outline,
                      color: Color(0xFF00E6A7), size: 18),
                  label: const Text('Este es mi puesto',
                      style: TextStyle(
                          color: Color(0xFF00E6A7),
                          fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(bool isMe, bool isActive) {
    if (isMe) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF00E6A7).withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('Tú',
            style: TextStyle(
                color: Color(0xFF00E6A7),
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.green.withOpacity(0.15)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isActive ? 'Activo' : 'Inactivo',
        style: TextStyle(
          color: isActive ? Colors.greenAccent : Colors.white38,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}