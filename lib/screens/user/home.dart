import 'package:flutter/material.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:areaguardian/screens/auth/login.dart';

import 'package:areaguardian/services/firestore_service.dart';
import 'package:areaguardian/services/location_service.dart';
import 'package:areaguardian/services/vendor_foreground_service.dart';
import 'package:areaguardian/services/auth_service.dart';
import 'package:areaguardian/services/session_service.dart';
import 'package:areaguardian/models/vendor_model.dart';
import 'package:areaguardian/widgets/profile_avatar.dart';
import 'package:areaguardian/screens/user/shake_training_screen.dart';

// ==========================================
// PANTALLA PRINCIPAL — HOME
// ==========================================
class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.onOpenMap, this.onOpenProfile});

  final VoidCallback? onOpenMap;
  final VoidCallback? onOpenProfile;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // ── Estado de sesión ──────────────────────────────────────────────────────
  bool _isLoggedIn = false;
  String _userName = '';
  String _userEmail = '';
  String emergencyContact = 'Sin contacto de emergencia';

  // Estado del puesto del vendedor y su proximidad al punto fijo.
  final LocationService _locationService = LocationService();
  final FirestoreService _firestoreService = FirestoreService();
  Timer? _vendorProximityTimer;
  StreamSubscription<VendorModel?>? _vendorSubscription;
  String _vendorId = '';
  double? _vendorLatitude;
  double? _vendorLongitude;
  double _vendorDistanceMeters = 0;
  bool _isVendor = false;
  bool _isVendorActive = false;
  bool _isNearVendorPost = false;
  bool _isVendorLocationTracking = false;
  int _shakeTrainingCompletions = 0;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final vendorId = prefs.getString('vendor_id') ?? '';
    final isVendor = (prefs.getString('user_role') ?? '') == 'vendor';
    setState(() {
      _isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      _userName =
          prefs.getString('vendor_name') ?? prefs.getString('user_name') ?? '';
      _userEmail = FirebaseAuth.instance.currentUser?.email ?? '';
      emergencyContact =
          prefs.getString('contact') ?? 'Sin contacto de emergencia';
      _vendorId = vendorId;
      _isVendor = isVendor;
      _vendorLatitude = prefs.getDouble('vendor_latitude');
      _vendorLongitude = prefs.getDouble('vendor_longitude');
      _shakeTrainingCompletions =
          prefs.getInt(ShakeTrainingScreen.completionCountKey) ?? 0;
    });

    if (!isVendor || vendorId.isEmpty) return;
    _watchVendor(vendorId);
    await _checkVendorProximity();
    _vendorProximityTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkVendorProximity(),
    );
  }

  void _watchVendor(String vendorId) {
    _vendorSubscription?.cancel();
    _vendorSubscription = _firestoreService.watchVendor(vendorId).listen((
      vendor,
    ) {
      if (!mounted || vendor == null) return;
      setState(() {
        _isVendorActive = vendor.isActive;
        if (vendor.latitude != 0 || vendor.longitude != 0) {
          _vendorLatitude = vendor.latitude;
          _vendorLongitude = vendor.longitude;
        }
      });
      _syncVendorLocationTracking(vendor.isActive).catchError((Object error) {
        debugPrint('No se pudo mantener activo el puesto: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo iniciar el servicio de puesto activo.'),
            ),
          );
        }
      });
    });
  }

  Future<void> _syncVendorLocationTracking(bool isActive) async {
    if (isActive) {
      if (_isVendorLocationTracking) return;
      await VendorForegroundService.start();
      _isVendorLocationTracking = true;
      await _locationService.startVendorLocationUpdates(
        onLocationUpdate: (position) =>
            _firestoreService.updateVendorCurrentLocation(
              vendorId: _vendorId,
              latitude: position.latitude,
              longitude: position.longitude,
            ),
      );
      return;
    }

    _isVendorLocationTracking = false;
    _locationService.stopVendorLocationUpdates();
    await VendorForegroundService.stopVendor();
  }

  Future<void> _checkVendorProximity() async {
    if (!_isVendor ||
        _isVendorActive ||
        _vendorId.isEmpty ||
        _vendorLatitude == null ||
        _vendorLongitude == null) {
      return;
    }

    final position = await _locationService.getCurrentLocationOrNull();
    if (position == null || !mounted) return;

    final distance = _locationService.distanceBetween(
      position,
      _vendorLatitude!,
      _vendorLongitude!,
    );
    final isNear = distance <= LocationService.vendorProximityRadiusMeters;
    setState(() {
      _vendorDistanceMeters = distance;
      _isNearVendorPost = isNear;
    });
  }

  Future<void> _activateVendor() async {
    if (_vendorId.isEmpty || (!_isVendorActive && !_isNearVendorPost)) {
      if (mounted && !_isVendorActive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acércate a tu puesto para activarlo.')),
        );
      }
      return;
    }
    final nextActiveState = !_isVendorActive;
    try {
      if (nextActiveState) await VendorForegroundService.start();
      await _firestoreService.setVendorActive(
        vendorId: _vendorId,
        isActive: nextActiveState,
      );
      await _syncVendorLocationTracking(nextActiveState);
      if (!mounted) return;
      setState(() {
        _isVendorActive = nextActiveState;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isVendorActive
                ? 'Tu puesto ahora está activo para la comunidad.'
                : 'Tu puesto quedó desconectado de la red.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo activar el puesto: $e')),
      );
      if (nextActiveState && !_isVendorActive) {
        await VendorForegroundService.stopVendor();
      }
    }
  }

  Future<void> _handleLogout() async {
    if (_isVendor) {
      _isVendorLocationTracking = false;
      _locationService.stopVendorLocationUpdates();
      try {
        await VendorForegroundService.stop();
      } catch (error) {
        debugPrint('No se pudo detener el servicio de puesto: $error');
      }
    }
    await AuthService().signOut();
    await SessionService().clearLocalSession();
    setState(() {
      _isLoggedIn = false;
      _userName = '';
      _userEmail = '';
    });
  }

  Future<void> _openShakeTraining() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ShakeTrainingScreen()),
    );
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _shakeTrainingCompletions =
          prefs.getInt(ShakeTrainingScreen.completionCountKey) ?? 0;
    });
  }

  @override
  void dispose() {
    _vendorProximityTimer?.cancel();
    _vendorSubscription?.cancel();
    _locationService.stopVendorLocationUpdates();
    super.dispose();
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              if (_isVendor) ...[
                _buildVendorActivationCard(),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 24),
              _isLoggedIn ? _buildLoggedInCard() : _buildLoginCard(),
              const SizedBox(height: 16),
              if (_isLoggedIn && _shakeTrainingCompletions == 0) ...[
                _buildShakeTrainingCard(),
                const SizedBox(height: 16),
              ],
              _buildContactCard(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShakeTrainingCard() {
    return InkWell(
      onTap: _openShakeTraining,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1D2030),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFFB300).withValues(alpha: 0.5),
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.vibration, color: Color(0xFFFFB300), size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Practica tu agitación',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Prueba el gesto sin enviar ninguna alerta.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────
  Widget _buildVendorActivationCard() {
    final statusColor = _isVendorActive
        ? const Color(0xFF00E6A7)
        : (_isNearVendorPost ? Colors.orangeAccent : Colors.white54);
    final statusText = _isVendorActive
        ? 'Puesto activo para la comunidad'
        : _isNearVendorPost
        ? '¿Estás en tu puesto? ¿Deseas activarlo?'
        : 'A ${_vendorDistanceMeters.toStringAsFixed(0)} m de tu puesto';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2030),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isVendorActive ? Icons.storefront : Icons.location_on,
                color: statusColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _activateVendor,
              icon: const Icon(Icons.power_settings_new),
              label: Text(
                _isVendorActive ? 'Desactivar mi puesto' : 'Activar mi puesto',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isVendorActive
                    ? Colors.white10
                    : const Color(0xFF00E6A7),
                foregroundColor: _isVendorActive ? Colors.white : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: const [
              Icon(Icons.cell_tower, color: Color(0xFF00E6A7), size: 26),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'AreaGuardian',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (_isLoggedIn)
          Semantics(
            label: 'Abrir perfil',
            button: true,
            child: InkWell(
              onTap: widget.onOpenProfile,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: ProfileAvatar(size: 36),
              ),
            ),
          ),
      ],
    );
  }

  // ── TARJETA LOGUEADO ──────────────────────────────────────────────────────
  Widget _buildLoggedInCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2030),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ProfileAvatar(size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userName.isNotEmpty ? _userName : 'Mi cuenta',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (_userEmail.isNotEmpty)
                      Text(
                        _userEmail,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white38, size: 20),
                onPressed: _handleLogout,
                tooltip: 'Cerrar sesión',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white12),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.map_outlined,
                  label: 'Ver Mapa',
                  onTap: widget.onOpenMap ?? () {},
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.person_outline,
                  label: 'Mi Perfil',
                  onTap: widget.onOpenProfile ?? () {},
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF00E6A7).withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF00E6A7).withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF00E6A7), size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF00E6A7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── TARJETA LOGIN ─────────────────────────────────────────────────────────
  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2030),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Únete a la red de vendedores',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Inicia sesión para acceder al mapa, registrar tu puesto y conectar con tu comunidad.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
                _loadPreferences();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.g_mobiledata, size: 24, color: Colors.black),
                  SizedBox(width: 8),
                  Text(
                    'Continuar con Google',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
                _loadPreferences();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.apple, size: 22, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Continuar con Apple',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── TARJETA CONTACTO ──────────────────────────────────────────────────────
  Widget _buildContactCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2030),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00E6A7).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.person_outline,
              color: Color(0xFF00E6A7),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Contacto de emergencia',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
                Text(
                  emergencyContact,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: widget.onOpenProfile,
            child: const Icon(
              Icons.chevron_right,
              color: Colors.white24,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}
