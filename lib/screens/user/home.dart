import 'package:flutter/material.dart';

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:areaguardian/screens/auth/login.dart';
import 'package:areaguardian/screens/map_dashboard_screen.dart';
import 'package:areaguardian/screens/account_config_screen.dart';

import 'emergency.dart';

import 'package:vibration/vibration.dart';
import 'package:areaguardian/services/firestore_service.dart';
import 'package:areaguardian/services/location_service.dart';
import 'package:areaguardian/services/protection_service.dart';

// ==========================================
// PANTALLA PRINCIPAL — HOME
// ==========================================
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  // ── Estado de sesión ──────────────────────────────────────────────────────
  bool _isLoggedIn = false;
  String _userName = '';
  String _userEmail = '';

  // ── Estado de seguridad ───────────────────────────────────────────────────
  final ProtectionService _protectionService = ProtectionService.shared;
  String emergencyContact = 'Sin contacto de emergencia';
  DateTime? _lastAlertTime;
  String? _activeEmergencyId;

  // Estado del puesto del vendedor y su proximidad al punto fijo.
  final LocationService _locationService = LocationService();
  final FirestoreService _firestoreService = FirestoreService();
  Timer? _vendorProximityTimer;
  String _vendorId = '';
  double? _vendorLatitude;
  double? _vendorLongitude;
  double _vendorDistanceMeters = 0;
  bool _isVendor = false;
  bool _isVendorActive = false;
  bool _isNearVendorPost = false;
  bool _showVendorActivationPrompt = false;

  // ── Sensores y audio ──────────────────────────────────────────────────────
  late AudioPlayer _audioPlayer;

  // ── Animación del escudo ──────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initAudio();
    _loadPreferences();
    _setupPulseAnimation();
    _protectionService.addListener(_onProtectionChanged);
    _protectionService.onEmergencyTriggered = _triggerAlarm;
  }

  void _onProtectionChanged() {
    if (mounted) setState(() {});
  }

  void _setupPulseAnimation() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initAudio() async {
    try {
      await _audioPlayer.setAsset('assets/audio/alarm.mp3');
      await _audioPlayer.setLoopMode(LoopMode.one);
    } catch (e) {
      debugPrint('Error al cargar audio: $e');
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final vendorId = prefs.getString('vendor_id') ?? '';
    final isVendor = (prefs.getString('user_role') ?? '') == 'vendor';
    setState(() {
      _isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      _userName = prefs.getString('vendor_name') ?? '';
      _userEmail = prefs.getString('user_email') ?? '';
      emergencyContact =
          prefs.getString('contact') ?? 'Sin contacto de emergencia';
      _vendorId = vendorId;
      _isVendor = isVendor;
      _vendorLatitude = prefs.getDouble('vendor_latitude');
      _vendorLongitude = prefs.getDouble('vendor_longitude');
    });

    if (!isVendor || vendorId.isEmpty) return;
    final vendor = await _firestoreService.getVendor(vendorId);
    if (!mounted) return;
    setState(() => _isVendorActive = vendor?.isActive ?? false);
    await _checkVendorProximity();
    _vendorProximityTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkVendorProximity(),
    );
  }

  Future<void> _checkVendorProximity() async {
    if (!_isVendor ||
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
      _showVendorActivationPrompt = isNear && !_isVendorActive;
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
    try {
      await _firestoreService.setVendorActive(
        vendorId: _vendorId,
        isActive: !_isVendorActive,
      );
      if (!mounted) return;
      setState(() {
        _isVendorActive = !_isVendorActive;
        _showVendorActivationPrompt = _isNearVendorPost && !_isVendorActive;
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
    }
  }

  // ── Guardia ───────────────────────────────────────────────────────────────
  void _toggleGuardia() {
    if (_protectionService.isProtected) {
      _deactivateGuard();
    } else {
      _activateGuard();
    }
  }

  void _activateGuard() {
    _protectionService.activate();
  }

  void _deactivateGuard() {
    _protectionService.deactivate();
  }

  void _triggerAlarm() async {
    final prefs = await SharedPreferences.getInstance();
    final position = await LocationService().getCurrentLocationForEmergency();
    if (position == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo obtener tu ubicación exacta.'),
          ),
        );
      }
      return;
    }

    final userId =
        prefs.getString('user_id') ?? prefs.getString('client_id') ?? '';
    final userName =
        prefs.getString('user_name') ??
        prefs.getString('vendor_name') ??
        'Usuario AreaGuardian';
    final emergency = await FirestoreService().createEmergency(
      userId: userId,
      userName: userName,
      latitude: position.latitude,
      longitude: position.longitude,
    );
    _activeEmergencyId = emergency.id;
    _protectionService.setActiveEmergencyId(emergency.id);
    _lastAlertTime = DateTime.now();

    if (await Vibration.hasVibrator() ?? false) {
      await Vibration.vibrate(pattern: [0, 100, 100, 100, 100, 100]);
    }
    _protectionService.markAlarmActive();
    await EmergencyAlertService.sendSMSAlert(context);
    await _audioPlayer.seek(Duration.zero);
    await _audioPlayer.play();
  }

  void _cancelAlarm() async {
    await _audioPlayer.stop();
    final emergencyId = _protectionService.activeEmergencyId;
    if (emergencyId != null) {
      await FirestoreService().resolveEmergency(emergencyId);
      _protectionService.clearActiveEmergencyId();
      _activeEmergencyId = null;
    }
    _protectionService.clearAlarm();
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', false);
    setState(() {
      _isLoggedIn = false;
      _userName = '';
      _userEmail = '';
    });
  }

  @override
  void dispose() {
    _protectionService.removeListener(_onProtectionChanged);
    _vendorProximityTimer?.cancel();
    _audioPlayer.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_protectionService.isAlarmActive) {
      return _buildEmergencyScreen();
    }
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
              _buildSecurityCard(),
              const SizedBox(height: 16),
              _isLoggedIn ? _buildLoggedInCard() : _buildLoginCard(),
              const SizedBox(height: 16),
              _buildContactCard(),
              const SizedBox(height: 24),
            ],
          ),
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
        Row(
          children: const [
            Icon(Icons.cell_tower, color: Color(0xFF00E6A7), size: 26),
            SizedBox(width: 8),
            Text(
              'AreaGuardian',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        if (_isLoggedIn)
          GestureDetector(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountConfigScreen()),
              );
              _loadPreferences();
            },
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF00E6A7).withOpacity(0.2),
                  child: Text(
                    _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      color: Color(0xFF00E6A7),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _userName.isNotEmpty ? _userName : 'Mi perfil',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_userEmail.isNotEmpty)
                      Text(
                        _userEmail,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── TARJETA DE SEGURIDAD ──────────────────────────────────────────────────
  Widget _buildSecurityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2030),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _protectionService.isProtected
              ? const Color(0xFF00E6A7).withOpacity(0.4)
              : Colors.white12,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _protectionService.isProtected
                    ? const Color(0xFF00E6A7).withOpacity(0.1)
                    : Colors.white.withOpacity(0.04),
                border: Border.all(
                  color: _protectionService.isProtected
                      ? const Color(0xFF00E6A7)
                      : Colors.white24,
                  width: 2.5,
                ),
              ),
              child: Icon(
                _protectionService.isProtected
                    ? Icons.security
                    : Icons.security_outlined,
                size: 48,
                color: _protectionService.isProtected
                    ? const Color(0xFF00E6A7)
                    : Colors.white38,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _protectionService.isProtected ? 'PROTEGIDO' : 'INACTIVO',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              color: _protectionService.isProtected
                  ? const Color(0xFF00E6A7)
                  : Colors.white38,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _protectionService.isProtected
                ? 'Agita 4 veces para activar la alarma'
                : 'Activa la guardia para comenzar',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (_protectionService.isProtected)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                4,
                (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _protectionService.shakeCount
                        ? const Color(0xFF00E6A7)
                        : Colors.white12,
                  ),
                ),
              ),
            ),
          if (_protectionService.isProtected) const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _protectionService.isProtected
                    ? Colors.white10
                    : const Color(0xFF00E6A7),
                foregroundColor: _protectionService.isProtected
                    ? Colors.white70
                    : Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: _protectionService.isProtected
                        ? Colors.white24
                        : Colors.transparent,
                  ),
                ),
              ),
              onPressed: _toggleGuardia,
              child: Text(
                _protectionService.isProtected
                    ? 'DESACTIVAR GUARDIA'
                    : 'ACTIVAR GUARDIA',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_protectionService.isProtected &&
              !_protectionService.isAlarmActive)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _triggerAlarm,
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text('ACTIVAR EMERGENCIA AHORA'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (_protectionService.isProtected &&
              !_protectionService.isAlarmActive)
            const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline, color: Colors.white24, size: 14),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '① Activa la guardia  ② Guarda el celular  ③ Agita 4 veces fuerte',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF00E6A7).withOpacity(0.15),
                child: Text(
                  _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Color(0xFF00E6A7),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
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
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MapDashboardScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.person_outline,
                  label: 'Mi Perfil',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AccountConfigScreen(),
                      ),
                    );
                    _loadPreferences();
                  },
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
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountConfigScreen()),
              );
              _loadPreferences();
            },
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

  // ── PANTALLA DE EMERGENCIA ────────────────────────────────────────────────
  Widget _buildEmergencyScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    '🚨 ALERTA DE EMERGENCIA ACTIVA',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Icon(Icons.cell_tower, color: Color(0xFF00E6A7)),
                  SizedBox(width: 8),
                  Text(
                    'AreaGuardian',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withOpacity(0.1),
                  border: Border.all(color: Colors.red, width: 2.5),
                ),
                child: const Center(
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 70,
                    color: Colors.red,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'EMERGENCIA',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '¡Toca CANCELAR si fue un error!',
                style: TextStyle(color: Colors.white60),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D2030),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      color: Colors.white54,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      emergencyContact,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    _cancelAlarm();
                    _deactivateGuard();
                  },
                  child: const Text(
                    'DESACTIVAR GUARDIA',
                    style: TextStyle(
                      color: Colors.white60,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _cancelAlarm,
                  child: const Text(
                    '✕  CANCELAR ALARMA — Fue un error',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
