import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ==========================================
// PANTALLA DE MAPA — OpenStreetMap (gratis)
// ==========================================
class MapDashboardScreen extends StatefulWidget {
  const MapDashboardScreen({super.key});

  @override
  State<MapDashboardScreen> createState() => _MapDashboardScreenState();
}

class _MapDashboardScreenState extends State<MapDashboardScreen> {
  final MapController _mapController = MapController();

  LatLng? _myLocation;
  LatLng? _myPuestoLocation;
  bool _isLoading = true;
  bool _locationDenied = false;

  String _myPuestoTitle = 'Mi Puesto';
  String _myVendorName = '';
  String _myAddress = '';

  _Puesto? _selectedPuesto;

  // Puestos simulados — reemplazar con Firestore o backend real
  final List<_Puesto> _puestosVecinos = [
    _Puesto(
      id: '1',
      title: 'Puesto 1',
      vendorName: 'María López',
      address: 'Carrera 96H #17-20',
      location: const LatLng(4.6740, -74.1470),
      isActive: true,
    ),
    _Puesto(
      id: '2',
      title: 'Puesto 2',
      vendorName: 'Carlos Cortés',
      address: 'Carrera 96H #17-35',
      location: const LatLng(4.6745, -74.1460),
      isActive: true,
    ),
    _Puesto(
      id: '3',
      title: 'Puesto 3',
      vendorName: 'Ana García',
      address: 'Calle 17 #96-10',
      location: const LatLng(4.6735, -74.1480),
      isActive: false,
    ),
    _Puesto(
      id: '4',
      title: 'Puesto 4',
      vendorName: 'Juan Rojas',
      address: 'Calle 17 #96-22',
      location: const LatLng(4.6750, -74.1455),
      isActive: true,
    ),
    _Puesto(
      id: '5',
      title: 'Puesto 5',
      vendorName: 'Laura Méndez',
      address: 'Carrera 96 #16-80',
      location: const LatLng(4.6730, -74.1490),
      isActive: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadMyPuesto();
    _getCurrentLocation();
  }

  Future<void> _loadMyPuesto() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myPuestoTitle = prefs.getString('puesto_title') ?? 'Mi Puesto';
      _myVendorName = prefs.getString('vendor_name') ?? '';
      _myAddress = prefs.getString('vendor_address') ?? '';
    });
  }

  Future<void> _getCurrentLocation() async {
    final status = await Permission.location.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      setState(() {
        _locationDenied = true;
        _isLoading = false;
        _myLocation = const LatLng(4.6742, -74.1468);
        _myPuestoLocation = const LatLng(4.6742, -74.1468);
      });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _myLocation = LatLng(position.latitude, position.longitude);
        _myPuestoLocation = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _myLocation = const LatLng(4.6742, -74.1468);
        _myPuestoLocation = const LatLng(4.6742, -74.1468);
        _isLoading = false;
      });
    }
  }

  void _centerOnMe() {
    if (_myLocation != null) {
      _mapController.move(_myLocation!, 17);
    }
  }

  Future<void> _navigateTo(_Puesto puesto) async {
    final lat = puesto.location.latitude;
    final lng = puesto.location.longitude;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF00E6A7)))
                  : Stack(
                      children: [
                        _buildMap(),
                        _buildLegend(),
                        _buildCenterButton(),
                        if (_locationDenied) _buildLocationWarning(),
                        if (_selectedPuesto != null) _buildPuestoCard(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final activos = _puestosVecinos.where((p) => p.isActive).length;
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
                'Fontibón • ${_puestosVecinos.length} puestos • $activos activos',
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

  // ── MAPA ──────────────────────────────────────────────────────────────────
  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _myLocation ?? const LatLng(4.6742, -74.1468),
        initialZoom: 16.5,
        onTap: (_, __) => setState(() => _selectedPuesto = null),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.areaguardian',
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
                  onTap: () => setState(() => _selectedPuesto = _Puesto(
                        id: 'me',
                        title: _myPuestoTitle,
                        vendorName: _myVendorName,
                        address: _myAddress,
                        location: _myPuestoLocation!,
                        isActive: true,
                        isMe: true,
                      )),
                  child: _buildMarkerWidget(
                    color: const Color(0xFF00E6A7),
                    icon: Icons.storefront,
                    isMe: true,
                  ),
                ),
              ),

            // Puestos vecinos
            ..._puestosVecinos.map(
              (puesto) => Marker(
                point: puesto.location,
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => setState(() => _selectedPuesto = puesto),
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
    return Positioned(
      bottom: _selectedPuesto != null ? 240 : 20,
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
    final puesto = _selectedPuesto!;
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
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Info del puesto
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: puesto.isMe
                        ? const Color(0xFF00E6A7).withOpacity(0.12)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: puesto.isMe
                          ? const Color(0xFF00E6A7).withOpacity(0.4)
                          : Colors.white12,
                    ),
                  ),
                  child: Icon(
                    puesto.isMe ? Icons.storefront : Icons.store_outlined,
                    size: 26,
                    color: puesto.isMe
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
                              puesto.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildBadge(puesto),
                        ],
                      ),
                      if (puesto.vendorName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          puesto.vendorName,
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
                              puesto.address.isNotEmpty
                                  ? puesto.address
                                  : 'Sin dirección registrada',
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

            // Botones
            if (!puesto.isMe)
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
                        _mapController.move(puesto.location, 18);
                        setState(() => _selectedPuesto = null);
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

            if (puesto.isMe)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color:
                            const Color(0xFF00E6A7).withOpacity(0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () =>
                      setState(() => _selectedPuesto = null),
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

  Widget _buildBadge(_Puesto puesto) {
    if (puesto.isMe) {
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
        color: puesto.isActive
            ? Colors.green.withOpacity(0.15)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        puesto.isActive ? 'Activo' : 'Inactivo',
        style: TextStyle(
          color: puesto.isActive ? Colors.greenAccent : Colors.white38,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ── MODELO PUESTO ─────────────────────────────────────────────────────────────
class _Puesto {
  final String id;
  final String title;
  final String vendorName;
  final String address;
  final LatLng location;
  final bool isActive;
  final bool isMe;

  const _Puesto({
    required this.id,
    required this.title,
    required this.vendorName,
    required this.address,
    required this.location,
    required this.isActive,
    this.isMe = false,
  });
}
