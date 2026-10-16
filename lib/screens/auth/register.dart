import 'package:areaguardian/models/vendor_model.dart';
import 'package:areaguardian/models/user_model.dart';
import 'package:areaguardian/widgets/bar_nav.dart';

import 'pick_location_map.dart';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:areaguardian/services/firestore_service.dart';
import 'package:areaguardian/services/session_service.dart';
import 'package:areaguardian/services/consent_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:areaguardian/screens/user/shake_training_screen.dart';

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  bool _isVendor = true; // Por defecto vendedor

  // Controladores separados para Dueño vs Puesto
  final _ownerNameController = TextEditingController(); // Dueño / Persona
  final _shopNameController =
      TextEditingController(); // Nombre del Puesto / Negocio
  final _addressController = TextEditingController();

  // Coordenadas fijas seleccionadas exclusivamente para el local comercial
  LatLng? _selectedShopCoords;
  bool _isLoading = false;
  bool _isCheckingProfile = true;
  String? _profileCheckError;

  final FirestoreService _firestoreService = FirestoreService();
  final SessionService _sessionService = SessionService();
  final Geocoding _geocoding = Geocoding();

  @override
  void initState() {
    super.initState();
    _checkForExistingProfile();
  }

  Future<void> _checkForExistingProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isCheckingProfile = false);
      return;
    }

    try {
      final profileExists = await _sessionService.restoreSession(user);
      if (!mounted) return;
      if (profileExists) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const AppShell(initialIndex: 0),
          ),
        );
      } else {
        setState(() => _isCheckingProfile = false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _profileCheckError = 'No se pudo verificar tu perfil: $error';
        _isCheckingProfile = false;
      });
    }
  }

  // Función para abrir el mapa y capturar el punto exacto del PUESTO
  Future<void> _openMapPicker() async {
    final LatLng? result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PickLocationScreen()),
    );

    if (result != null) {
      String address =
          'Lat: ${result.latitude.toStringAsFixed(6)}, Lng: ${result.longitude.toStringAsFixed(6)}';
      try {
        final placemarks = await _geocoding.placemarkFromCoordinates(
          result.latitude,
          result.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          address = [place.street, place.subLocality, place.locality]
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .join(', ');
        }
      } catch (_) {
        // Se conservan las coordenadas si el dispositivo no tiene geocodificador.
      }

      setState(() {
        _selectedShopCoords = result;
        _addressController.text = address;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📍 Ubicación fija del puesto guardada correctamente'),
        ),
      );
    }
  }

  Future<void> _completeRegistration() async {
    // Validaciones estrictas separadas
    if (_ownerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa tu nombre como propietario'),
        ),
      );
      return;
    }

    if (_isVendor &&
        (_shopNameController.text.trim().isEmpty ||
            _selectedShopCoords == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor completa los datos del puesto y marca su ubicación fija en el mapa',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw StateError(
          'Debes iniciar sesión con Google antes de registrar un puesto.',
        );
      }
      final String userId = currentUser.uid;
      final String? vendorId = _isVendor ? userId : null;

      if (await _sessionService.restoreSession(currentUser)) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const AppShell(initialIndex: 0),
          ),
        );
        return;
      }

      await _firestoreService.saveUserProfile(
        UserModel(
          id: userId,
          name: _ownerNameController.text.trim(),
          email: currentUser.email ?? '',
          phone: '',
          isVendor: _isVendor,
          vendorId: vendorId,
        ),
      );

      if (_isVendor) {
        // --- REGISTRO DEL PUESTO FIJO ---
        final newVendor = VendorModel(
          id: userId,
          userId: userId,

          // 1. Identidad del Negocio / Puesto
          shopName: _shopNameController.text.trim(),
          address: _addressController.text.trim(),
          category: 'Comercio General',
          latitude: _selectedShopCoords!.latitude, // Coordenada fija del local
          longitude:
              _selectedShopCoords!.longitude, // Coordenada fija del local
          // Identidad del dueño, sin guardar su ubicación personal.
          vendorName: _ownerNameController.text.trim(),

          nequiNumber: '',
          daviplataNumber: '',
          isActive: false,
          lastSeen: null,
        );

        await _firestoreService.saveVendorProfile(newVendor);
      }

      await _sessionService.restoreSession(currentUser);
      await ConsentService().syncAcceptedConsent(userId);

      if (!mounted) return;

      var startTraining = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        final hasCompletedTraining =
            (prefs.getInt(ShakeTrainingScreen.completionCountKey) ?? 0) > 0;
        final hasShownInvitation =
            prefs.getBool(ShakeTrainingScreen.invitationShownKey) ?? false;
        if (!hasCompletedTraining && !hasShownInvitation) {
          await prefs.setBool(ShakeTrainingScreen.invitationShownKey, true);
          if (!mounted) return;
          startTraining =
              await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('¿Quieres probar la agitación?'),
                  content: const Text(
                    'Puedes practicar de forma segura. No se enviará ninguna '
                    'alerta ni se contactará a nadie.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Ahora no'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Practicar'),
                    ),
                  ],
                ),
              ) ??
              false;
        }
      } catch (error) {
        debugPrint('No se pudo mostrar la invitación a practicar: $error');
      }

      if (!mounted) return;
      if (startTraining) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (trainingContext) => ShakeTrainingScreen(
              onDone: () => Navigator.of(trainingContext).pushAndRemoveUntil(
                MaterialPageRoute<void>(
                  builder: (_) => const AppShell(initialIndex: 0),
                ),
                (route) => false,
              ),
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const AppShell(initialIndex: 0),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al registrar: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingProfile) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00E6A7)),
        ),
      );
    }

    if (_profileCheckError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_profileCheckError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isCheckingProfile = true;
                      _profileCheckError = null;
                    });
                    _checkForExistingProfile();
                  },
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Registro en la Red',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
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
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
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
                      labelStyle: TextStyle(
                        color: _isVendor ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
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
                      labelStyle: TextStyle(
                        color: !_isVendor ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (val) => setState(() => _isVendor = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 1. SECCIÓN DUEÑO / PROPIETARIO
              const Text(
                'Tu Nombre o Apodo (Propietario)',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _ownerNameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ej: Carlos Cortés / María Pérez',
                  hintStyle: const TextStyle(color: Colors.white24),
                  prefixIcon: const Icon(
                    Icons.person_outline,
                    color: Color(0xFF00E6A7),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1D2030),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Campos exclusivos para Vendedor (Negocio / Puesto físico)
              if (_isVendor) ...[
                const Divider(color: Colors.white24, height: 32),
                const Text(
                  'Información del Negocio',
                  style: TextStyle(
                    color: Color(0xFF00E6A7),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Nombre del Puesto o Local',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _shopNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Ej: Puesto 3 - Variedades Doña Mary',
                    hintStyle: const TextStyle(color: Colors.white24),
                    prefixIcon: const Icon(
                      Icons.store,
                      color: Color(0xFF00E6A7),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1D2030),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Botón para invocar el selector de mapa exclusivamente para la infraestructura del local
                const Text(
                  'Ubicación Fija del Puesto en el Mapa',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00E6A7)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _openMapPicker,
                  icon: const Icon(Icons.map, color: Color(0xFF00E6A7)),
                  label: Text(
                    _selectedShopCoords == null
                        ? 'Marcar ubicación exacta del puesto'
                        : '✓ Puesto ubicado (Lat: ${_selectedShopCoords!.latitude.toStringAsFixed(4)})',
                    style: const TextStyle(
                      color: Color(0xFF00E6A7),
                      fontWeight: FontWeight.bold,
                    ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _completeRegistration,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(
                          _isVendor
                              ? 'Guardar Negocio y Activar Red'
                              : 'Entrar como Vecino de Apoyo',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
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
