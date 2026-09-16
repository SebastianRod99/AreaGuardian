import 'package:areaguardian/models/vendor_model.dart';
import 'package:areaguardian/screens/map_dashboard_screen.dart';
import 'pick_location_map.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:areaguardian/services/firestore_service.dart';
import 'package:areaguardian/services/location_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  bool _isVendor = true; // Por defecto vendedor

  // Controladores separados para Dueño vs Puesto
  final _ownerNameController = TextEditingController(); // Dueño / Persona
  final _shopNameController = TextEditingController();   // Nombre del Puesto / Negocio
  final _addressController = TextEditingController();    // Dirección física / Sector del puesto

  // Coordenadas fijas seleccionadas exclusivamente para el local comercial
  LatLng? _selectedShopCoords;
  bool _isLoading = false;

  final FirestoreService _firestoreService = FirestoreService();
  final LocationService _locationService = LocationService();

  // Función para abrir el mapa y capturar el punto exacto del PUESTO
  Future<void> _openMapPicker() async {
    final LatLng? result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PickLocationScreen()),
    );

    if (result != null) {
      setState(() {
        _selectedShopCoords = result;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📍 Ubicación fija del puesto guardada correctamente')),
      );
    }
  }

  Future<void> _completeRegistration() async {
    // Validaciones estrictas separadas
    if (_ownerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingresa tu nombre como propietario')),
      );
      return;
    }

    if (_isVendor && (_shopNameController.text.trim().isEmpty || _addressController.text.trim().isEmpty || _selectedShopCoords == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa los datos del puesto y marca su ubicación fija en el mapa')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final String userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
      final prefs = await SharedPreferences.getInstance();

      if (_isVendor) {
        // --- OBTENER GPS EN VIVO DEL DUEÑO (SEPARADO DEL PUESTO) ---
        double liveLat = _selectedShopCoords!.latitude;
        double liveLng = _selectedShopCoords!.longitude;

        try {
          Position currentPos = await _locationService.getCurrentLocation();
          liveLat = currentPos.latitude;
          liveLng = currentPos.longitude;
        } catch (_) {
          // Si el GPS en vivo no responde al momento del registro, tomamos el del puesto como respaldo inicial
        }

        // --- REGISTRO DE VENDOR (Estructura Clara y Separada) ---
        final newVendor = VendorModel(
          id: userId,
          userId: userId,

          // 1. Identidad del Negocio / Puesto
          shopName: _shopNameController.text.trim(),
          category: 'Comercio General',
          latitude: _selectedShopCoords!.latitude,   // Coordenada fija del local
          longitude: _selectedShopCoords!.longitude, // Coordenada fija del local

          // 2. Identidad del Dueño / Persona y su GPS Dinámico
          vendorName: _ownerNameController.text.trim(), // Nombre real del dueño
          currentLatitude: liveLat,                    // GPS en tiempo real del dueño
          currentLongitude: liveLng,                   // GPS en tiempo real del dueño

          nequiNumber: '',
          daviplataNumber: '',
          isActive: true,
          lastSeen: DateTime.now(),
        );

        await _firestoreService.saveVendorProfile(newVendor);

        // Guardado local independiente en SharedPreferences
        await prefs.setString('vendor_id', userId);
        await prefs.setString('vendor_name', _ownerNameController.text.trim()); // Nombre de la dueña/dueño
        await prefs.setString('puesto_title', _shopNameController.text.trim()); // Nombre del negocio
        await prefs.setString('vendor_address', _addressController.text.trim());

        // Coordenadas fijas del puesto en el mapa principal
        await prefs.setDouble('vendor_latitude', _selectedShopCoords!.latitude);
        await prefs.setDouble('vendor_longitude', _selectedShopCoords!.longitude);
      } else {
        // --- REGISTRO DE CLIENTE / VECINO ---
        await prefs.setString('client_id', userId);
        await prefs.setString('user_name', _ownerNameController.text.trim());
      }

      await prefs.setString('user_role', _isVendor ? 'vendor' : 'client');
      await prefs.setBool('is_registered', true);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MapDashboardScreen()),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al registrar: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Registro en la Red', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.security, size: 56, color: Color(0xFF00E6A7)),
              const SizedBox(height: 16),
              const Text(
                'Únete a la Red de Apoyo',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 30),

              // Selector de Rol (Vendedor vs Cliente)
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Vendedor')),
                      selected: _isVendor,
                      selectedColor: const Color(0xFF00E6A7),
                      backgroundColor: const Color(0xFF1D2030),
                      labelStyle: TextStyle(color: _isVendor ? Colors.black : Colors.white70, fontWeight: FontWeight.bold),
                      onSelected: (val) => setState(() => _isVendor = true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Cliente')),
                      selected: !_isVendor,
                      selectedColor: const Color(0xFF00E6A7),
                      backgroundColor: const Color(0xFF1D2030),
                      labelStyle: TextStyle(color: !_isVendor ? Colors.black : Colors.white70, fontWeight: FontWeight.bold),
                      onSelected: (val) => setState(() => _isVendor = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 1. SECCIÓN DUEÑO / PROPIETARIO
              const Text('Tu Nombre o Apodo (Propietario)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _ownerNameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ej: Carlos Cortés / María Pérez',
                  hintStyle: const TextStyle(color: Colors.white24),
                  prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF00E6A7)),
                  filled: true,
                  fillColor: const Color(0xFF1D2030),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),

              // Campos exclusivos para Vendedor (Negocio / Puesto físico)
              if (_isVendor) ...[
                const Divider(color: Colors.white24, height: 32),
                const Text('Información del Negocio', style: TextStyle(color: Color(0xFF00E6A7), fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),

                const Text('Nombre del Puesto o Local', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _shopNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Ej: Puesto 3 - Variedades Doña Mary',
                    hintStyle: const TextStyle(color: Colors.white24),
                    prefixIcon: const Icon(Icons.store, color: Color(0xFF00E6A7)),
                    filled: true,
                    fillColor: const Color(0xFF1D2030),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),

                const Text('Dirección o Sector del Puesto', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _addressController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Ej: Carrera 96H #17 (Plaza Central)',
                    hintStyle: const TextStyle(color: Colors.white24),
                    prefixIcon: const Icon(Icons.location_on_outlined, color: Color(0xFF00E6A7)),
                    filled: true,
                    fillColor: const Color(0xFF1D2030),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),

                // Botón para invocar el selector de mapa exclusivamente para la infraestructura del local
                const Text('Ubicación Fija del Puesto en el Mapa', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00E6A7)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _openMapPicker,
                  icon: const Icon(Icons.map, color: Color(0xFF00E6A7)),
                  label: Text(
                    _selectedShopCoords == null
                        ? 'Marcar ubicación exacta del puesto'
                        : '✓ Puesto ubicado (Lat: ${_selectedShopCoords!.latitude.toStringAsFixed(4)})',
                    style: const TextStyle(color: Color(0xFF00E6A7), fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 30),
              ],

              // Botón Final
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E6A7),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _completeRegistration,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(_isVendor ? 'Guardar Negocio y Activar Red' : 'Entrar como Vecino de Apoyo',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}