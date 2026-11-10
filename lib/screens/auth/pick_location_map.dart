import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/location_service.dart';

class PickLocationScreen extends StatefulWidget {
  const PickLocationScreen({super.key});

  @override
  State<PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<PickLocationScreen> {
  final MapController _mapController = MapController();
  LatLng? _selectedPosition;
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _loadInitialLocation();
  }

  Future<void> _loadInitialLocation() async {
    final position = await LocationService().getCurrentLocationOrNull();
    if (!mounted) return;
    setState(() {
      _selectedPosition = position == null
          ? null
          : LatLng(position.latitude, position.longitude);
      _isLoadingLocation = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedPosition = _selectedPosition;
    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D2030),
        elevation: 0,
        title: const Text(
          'Ubica tu Puesto en el Mapa',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoadingLocation
          ? const Center(child: CircularProgressIndicator())
          : selectedPosition == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No se pudo obtener tu ubicación. Activa el permiso de ubicación y vuelve a abrir esta pantalla.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Stack(
              children: [
                // 1. Mapa interactivo
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: selectedPosition,
                    initialZoom: 16.0,
                    onPositionChanged: (position, hasGesture) {
                      if (hasGesture) {
                        setState(() {
                          _selectedPosition = position.center;
                        });
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.areaguardian.app',
                    ),
                  ],
                ),

                // 2. Pin fijo en el centro de la pantalla que marca la ubicación exacta
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: 35,
                    ), // Ajuste visual para que la punta apunte al centro
                    child: Icon(
                      Icons.location_pin,
                      size: 48,
                      color: Color(0xFF00E6A7),
                    ),
                  ),
                ),

                // 3. Indicador flotante superior con instrucciones
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D2030).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF00E6A7).withOpacity(0.3),
                      ),
                    ),
                    child: const Text(
                      'Mueve el mapa para centrar el pin exactamente en la dirección de tu local comercial.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ),

                // 4. Botón inferior para confirmar la ubicación seleccionada
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E6A7),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        // Retornamos las coordenadas seleccionadas al formulario anterior
                        Navigator.pop(context, selectedPosition);
                      },
                      child: const Text(
                        'Confirmar Ubicación del Puesto',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
