import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:areaguardian/services/firestore_service.dart';
import 'package:areaguardian/services/location_service.dart';
import 'package:areaguardian/screens/map_dashboard_screen.dart';

class VendorHome extends StatefulWidget {
  const VendorHome({super.key});

  @override
  State<VendorHome> createState() => _VendorHomeState();
}

class _VendorHomeState extends State<VendorHome> {
  final LocationService _locationService = LocationService();
  final FirestoreService _firestoreService = FirestoreService();

  // Datos locales del vendedor
  String _vendorId = '';
  String _shopName = 'Mi Puesto';
  String _vendorName = 'Vendedor';

  // Coordenadas
  double? _shopLat;
  double? _shopLng;
  double? _currentLat;
  double? _currentLng;

  // Estado de proximidad y red
  double _distanceInMeters = 0.0;
  bool _isAtShop = false;
  bool _isActive = false;
  bool _isLoading = true;
  Timer? _proximityTimer;

  @override
  void initState() {
    super.initState();
    _initializeVendorData();
  }

  @override
  void dispose() {
    _proximityTimer
        ?.cancel(); // Cancelamos el temporizador al salir de la pantalla
    super.dispose();
  }

  // 1. Cargar la configuración guardada en el registro
  Future<void> _initializeVendorData() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _vendorId = prefs.getString('vendor_id') ?? '';
      _shopName = prefs.getString('puesto_title') ?? 'Mi Puesto';
      _vendorName = prefs.getString('user_name') ?? 'Vendedor';
      _shopLat = prefs.getDouble('vendor_latitude');
      _shopLng = prefs.getDouble('vendor_longitude');
    });

    final vendor = await _firestoreService.getVendor(_vendorId);
    if (mounted) setState(() => _isActive = vendor?.isActive ?? false);

    // Validamos la proximidad inicial de inmediato
    await _checkProximityAndUpdateStatus();

    // Configuramos un loop cada 15 segundos para monitorear el movimiento en vivo
    _proximityTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _checkProximityAndUpdateStatus();
    });

    setState(() => _isLoading = false);
  }

  // 2. MAGIA DE PROXIMIDAD Y ACTUALIZACIÓN AUTOMÁTICA
  Future<void> _checkProximityAndUpdateStatus() async {
    if (_vendorId.isEmpty || _shopLat == null || _shopLng == null) return;

    try {
      // Obtenemos las coordenadas GPS actuales del celular
      final currentPosition = await _locationService.getCurrentLocationOrNull();
      if (currentPosition == null) return;

      _currentLat = currentPosition.latitude;
      _currentLng = currentPosition.longitude;

      // Calculamos la distancia en metros entre el puesto fijo y el celular
      double distance = Geolocator.distanceBetween(
        _shopLat!,
        _shopLng!,
        _currentLat!,
        _currentLng!,
      );

      // Umbral de proximidad: 50 metros a la redonda se considera "en el puesto"
      bool nearShop = distance <= LocationService.vendorProximityRadiusMeters;

      setState(() {
        _distanceInMeters = distance;
        _isAtShop = nearShop;
      });

      // La posición del dueño se conserva únicamente en memoria local.
      // Solo una emergencia publica una posición en Firestore.
    } catch (e) {
      debugPrint('Error actualizando proximidad del vendedor: $e');
    }
  }

  Future<void> _activateVendor() async {
    if (!_isAtShop || _vendorId.isEmpty) return;
    await _firestoreService.setVendorActive(
      vendorId: _vendorId,
      isActive: true,
    );
    if (!mounted) return;
    setState(() => _isActive = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tu puesto ahora está activo para la comunidad.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _shopName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.map, color: Color(0xFF00E6A7)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MapDashboardScreen(),
                ),
              );
            },
            tooltip: 'Ver Mapa de la Red',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E6A7)),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Tarjeta de Estado de Proximidad Automático
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1D2030),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isAtShop
                              ? const Color(0xFF00E6A7)
                              : Colors.orangeAccent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _isAtShop ? Icons.store : Icons.directions_walk,
                            size: 48,
                            color: _isAtShop
                                ? const Color(0xFF00E6A7)
                                : Colors.orangeAccent,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _isAtShop
                                ? 'ESTÁS ATENDIENDO'
                                : 'FUERA DE TU PUESTO',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _isAtShop
                                  ? const Color(0xFF00E6A7)
                                  : Colors.orangeAccent,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isAtShop
                                ? 'Te encuentras en tu local comercial. Estado visible en verde para la red.'
                                : 'Estás a ${_distanceInMeters.toStringAsFixed(0)} metros de tu puesto. Te has marcado como ausente.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (!_isActive && _isAtShop)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E6A7),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _activateVendor,
                        icon: const Icon(Icons.power_settings_new),
                        label: const Text('¿Estás en tu puesto? Activarlo'),
                      ),
                    if (_isActive)
                      const Text(
                        'Puesto activo para la comunidad',
                        style: TextStyle(
                          color: Color(0xFF00E6A7),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Información del Comercial
                    const Text(
                      'Información del Negocio',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tileColor: const Color(0xFF1D2030),
                      leading: const Icon(
                        Icons.person,
                        color: Color(0xFF00E6A7),
                      ),
                      title: const Text(
                        'Comerciante',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      subtitle: Text(
                        _vendorName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tileColor: const Color(0xFF1D2030),
                      leading: const Icon(
                        Icons.location_on,
                        color: Color(0xFF00E6A7),
                      ),
                      title: const Text(
                        'Ubicación Fija del Puesto',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      subtitle: Text(
                        'Lat: ${_shopLat?.toStringAsFixed(4)}, Lng: ${_shopLng?.toStringAsFixed(4)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Botón para ir al Mapa General
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E6A7),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MapDashboardScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.map_outlined),
                      label: const Text(
                        'Abrir Mapa de la Red de Apoyo',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Botón de Forzar Verificación Manual (Útil para pruebas)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        setState(() => _isLoading = true);
                        await _checkProximityAndUpdateStatus();
                        setState(() => _isLoading = false);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '🔄 Proximidad recalculada: Distancia actual: ${_distanceInMeters.toStringAsFixed(1)}m',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                      label: const Text(
                        'Comprobar Ubicación Ahora',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
