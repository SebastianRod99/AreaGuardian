import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';

import 'emergency.dart'; // Importa tu servicio centralizado

import 'package:vibration/vibration.dart';
import 'package:areaguardian/services/firestore_service.dart';
import 'package:areaguardian/services/location_service.dart';
import 'package:areaguardian/services/protection_service.dart';

// ==========================================
// PANTALLA DEDICADA DE SEGURIDAD (TAB 1)
// ==========================================
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen>
    with TickerProviderStateMixin {
  final ProtectionService _protectionService = ProtectionService.shared;
  String emergencyContact = 'Sin contacto de emergencia';
  DateTime? _lastAlertTime;
  String? _activeEmergencyId;

  late AudioPlayer _audioPlayer;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initAudio();
    _loadContact();
    _protectionService.addListener(_onProtectionChanged);
    _protectionService.onEmergencyTriggered = _triggerAlarm;
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.93,
      end: 1.07,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  Future<void> _initAudio() async {
    try {
      await _audioPlayer.setAsset('assets/audio/alarm.mp3');
      await _audioPlayer.setLoopMode(LoopMode.one);
    } catch (e) {
      debugPrint('Error audio: $e');
    }
  }

  Future<void> _loadContact() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      emergencyContact =
          prefs.getString('contact') ?? 'Sin contacto de emergencia';
    });
  }

  void _onProtectionChanged() {
    if (mounted) setState(() {});
  }

  void _toggleGuardia() {
    _protectionService.isProtected ? _deactivate() : _activate();
  }

  void _activate() {
    _protectionService.activate();
  }

  void _deactivate() {
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

  @override
  void dispose() {
    _protectionService.removeListener(_onProtectionChanged);
    _audioPlayer.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_protectionService.isAlarmActive) return _buildEmergency();

    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Seguridad',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _protectionService.isProtected
                    ? 'Guardia activa — agita 4 veces para alertar'
                    : 'Activa la guardia para comenzar',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 40),
              Center(
                child: ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _protectionService.isProtected
                          ? const Color(0xFF00E6A7).withOpacity(0.08)
                          : Colors.white.withOpacity(0.04),
                      border: Border.all(
                        color: _protectionService.isProtected
                            ? const Color(0xFF00E6A7)
                            : Colors.white24,
                        width: 3,
                      ),
                    ),
                    child: Icon(
                      _protectionService.isProtected
                          ? Icons.security
                          : Icons.security_outlined,
                      size: 80,
                      color: _protectionService.isProtected
                          ? const Color(0xFF00E6A7)
                          : Colors.white24,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  _protectionService.isProtected ? 'PROTEGIDO' : 'INACTIVO',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                    color: _protectionService.isProtected
                        ? const Color(0xFF00E6A7)
                        : Colors.white24,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_protectionService.isProtected)
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      4,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: i < _protectionService.shakeCount ? 16 : 12,
                        height: i < _protectionService.shakeCount ? 16 : 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _protectionService.shakeCount
                              ? const Color(0xFF00E6A7)
                              : Colors.white12,
                        ),
                      ),
                    ),
                  ),
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
                      color: Color(0xFF00E6A7),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        emergencyContact,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _protectionService.isProtected
                        ? Colors.white10
                        : const Color(0xFF00E6A7),
                    foregroundColor: _protectionService.isProtected
                        ? Colors.white60
                        : Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
                      fontSize: 15,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_protectionService.isProtected &&
                  !_protectionService.isAlarmActive)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _triggerAlarm,
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: const Text('ACTIVAR EMERGENCIA AHORA'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              if (_protectionService.isProtected &&
                  !_protectionService.isAlarmActive)
                const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D2030),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline, color: Colors.white24, size: 16),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '① Activa la guardia  ② Guarda el celular en el bolsillo  ③ Agita con fuerza 4 veces',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmergency() {
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
              const Spacer(),
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withOpacity(0.1),
                  border: Border.all(color: Colors.red, width: 3),
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
                    _deactivate();
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
