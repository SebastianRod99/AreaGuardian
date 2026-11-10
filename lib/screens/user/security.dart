import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:areaguardian/services/firestore_service.dart';
import 'package:areaguardian/services/emergency_alert_service.dart';
import 'package:areaguardian/services/vendor_foreground_service.dart';
import 'package:areaguardian/services/app_telemetry_service.dart';
import 'package:areaguardian/models/emergency_model.dart';
import 'package:areaguardian/screens/user/shake_training_screen.dart';
import 'package:areaguardian/utils/helpers.dart';

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
  final EmergencyAlertService _emergencyAlertService = EmergencyAlertService();
  String emergencyContact = 'Sin contacto de emergencia';
  EmergencyModel? _activeEmergency;
  static const int _gracePeriodSeconds = 20;
  Timer? _gracePeriodTimer;
  DateTime? _gracePeriodEndsAt;
  int _graceSecondsRemaining = 0;
  bool _isCancellingAlarm = false;
  bool _smsIsOpening = false;
  bool _smsFallbackOpened = false;
  String? _smsError;
  bool _openSmsAfterGracePeriod = true;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _loadContact();
    unawaited(_restoreActiveEmergency());
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

  Future<void> _loadContact() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      emergencyContact =
          prefs.getString('contact') ?? 'Sin contacto de emergencia';
    });
  }

  Future<void> _restoreActiveEmergency() async {
    try {
      final emergency = await FirestoreService()
          .fetchCurrentUserActiveEmergency();
      if (!mounted || emergency == null) return;
      if (_activeEmergency?.id == emergency.id) return;

      _activeEmergency = emergency;
      if (!_protectionService.isProtected) {
        _protectionService.activate(listen: false);
      }
      if (_protectionService.activeEmergencyId != emergency.id) {
        _protectionService.markAlarmActive(emergency.id);
      }
      _startGracePeriod(emergency, openMessageWhenElapsed: false);
    } catch (error) {
      debugPrint('No se pudo restaurar la emergencia activa para SMS: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo recuperar el envío de SMS pendiente.'),
          ),
        );
      }
    }
  }

  void _onProtectionChanged() {
    if (mounted) setState(() {});
  }

  void _toggleGuardia() {
    if (_protectionService.isProtected) {
      unawaited(_deactivate());
    } else {
      unawaited(_activate());
    }
  }

  Future<void> _activate() async {
    try {
      await VendorForegroundService.startGuard();
      _protectionService.activate();
      await AppTelemetryService.logGuardActivated();
    } catch (error) {
      await VendorForegroundService.stopGuard();
      debugPrint('No se pudo iniciar la guardia en segundo plano: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo iniciar la guardia en segundo plano. Revisa los permisos de notificación.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _deactivate() async {
    _protectionService.deactivate();
    await VendorForegroundService.stopGuard();
  }

  void _triggerAlarm() {
    if (!mounted || !_protectionService.beginEmergencyActivation()) return;
    unawaited(_emergencyAlertService.vibrateConfirmation());
    unawaited(_submitEmergency());
  }

  Future<void> _submitEmergency() async {
    var activated = false;
    try {
      final hasNetworkTransport = await _hasNetworkTransport();
      final emergency = await _emergencyAlertService.createEmergency(
        persist: hasNetworkTransport,
      );
      if (emergency == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo obtener tu ubicación exacta.'),
            ),
          );
        }
        return;
      }
      _protectionService.markAlarmActive(emergency.id);
      _activeEmergency = emergency;
      activated = true;
      _startGracePeriod(emergency);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              emergency.id.startsWith('offline_')
                  ? 'Sin internet. El mensaje está listo para que lo envíes.'
                  : 'Solicitud enviada discretamente.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo enviar la solicitud: $error')),
        );
      }
    } finally {
      if (!activated) _protectionService.failEmergencyActivation();
    }
  }

  void _startGracePeriod(
    EmergencyModel emergency, {
    bool openMessageWhenElapsed = true,
  }) {
    _gracePeriodTimer?.cancel();
    _openSmsAfterGracePeriod = openMessageWhenElapsed;
    _smsError = null;
    _smsFallbackOpened = false;
    if (emergency.id.startsWith('offline_')) {
      _gracePeriodEndsAt = null;
      _graceSecondsRemaining = 0;
      if (mounted) setState(() {});
      unawaited(_prepareEmergencySms());
      return;
    }

    final emergencyCreatedAt = emergency.timestamp;
    final gracePeriodEndsAt = emergencyCreatedAt.add(
      const Duration(seconds: _gracePeriodSeconds),
    );
    if (!gracePeriodEndsAt.isAfter(DateTime.now())) {
      _gracePeriodEndsAt = null;
      _graceSecondsRemaining = 0;
      if (openMessageWhenElapsed) unawaited(_prepareEmergencySms());
      return;
    }
    _gracePeriodEndsAt = gracePeriodEndsAt;
    _updateGraceCountdown();
    _gracePeriodTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateGraceCountdown();
    });
  }

  void _updateGraceCountdown() {
    final deadline = _gracePeriodEndsAt;
    if (deadline == null) return;

    final remainingMilliseconds = deadline
        .difference(DateTime.now())
        .inMilliseconds;
    final remainingSeconds = (remainingMilliseconds / 1000).ceil();
    final gracePeriodEnded = remainingSeconds <= 0;
    if (mounted) {
      setState(() {
        _graceSecondsRemaining = remainingSeconds.clamp(0, _gracePeriodSeconds);
        if (gracePeriodEnded) _gracePeriodEndsAt = null;
      });
    }
    if (gracePeriodEnded) {
      _gracePeriodTimer?.cancel();
      if (_openSmsAfterGracePeriod) unawaited(_prepareEmergencySms());
    }
  }

  bool get _isGracePeriodActive =>
      _gracePeriodEndsAt?.isAfter(DateTime.now()) ?? false;

  Future<bool> _hasNetworkTransport() async {
    try {
      final connectivity = await Connectivity().checkConnectivity().timeout(
        const Duration(seconds: 2),
      );
      return !connectivity.contains(ConnectivityResult.none);
    } on TimeoutException catch (error) {
      debugPrint('La comprobación de red agotó el tiempo: $error');
      return true;
    } catch (error) {
      debugPrint('No se pudo comprobar la red: $error');
      return true;
    }
  }

  Future<void> _prepareEmergencySms() async {
    final emergency = _activeEmergency;
    if (emergency == null || _smsIsOpening) return;

    _smsIsOpening = true;
    _smsError = null;
    if (mounted) setState(() {});

    try {
      final rawContact = emergencyContact.trim();
      final phone = normalizeColombianMobileNumber(rawContact);
      if (phone == null) {
        _showSmsError('Configura un teléfono válido para tu contacto.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final userName =
          prefs.getString('user_name') ??
          prefs.getString('vendor_name') ??
          emergency.userName;
      final address = prefs.getString('vendor_address')?.trim();
      final locationName = address != null && address.isNotEmpty
          ? address
          : emergency.role == 'vendor' && emergency.shopName.trim().isNotEmpty
          ? emergency.shopName
          : 'tu ubicación actual';
      final body =
          'AreaGuardian: ${_withoutEmoji(userName)} activó una alerta en '
          '${_withoutEmoji(locationName)}. '
          'Verifica la situación y llama al 123 si requiere ayuda. Ubicación: '
          'https://maps.google.com/?q=${emergency.latitude},${emergency.longitude}';
      final smsUri = Uri(
        scheme: 'sms',
        path: phone,
        queryParameters: {'body': body},
      );

      if (!await launchUrl(smsUri, mode: LaunchMode.externalApplication)) {
        _smsFallbackOpened = false;
        _showSmsError('No se pudo abrir la aplicación de mensajes.');
      } else {
        _smsFallbackOpened = true;
        if (mounted) setState(() {});
      }
    } catch (error) {
      _showSmsError('No se pudo preparar el mensaje SMS.');
      debugPrint('No se pudo abrir el compositor SMS: $error');
    } finally {
      _smsIsOpening = false;
      if (mounted) setState(() {});
    }
  }

  String _withoutEmoji(String value) {
    final textCodePoints = value.runes.where((codePoint) {
      final isEmojiRange =
          (codePoint >= 0x1F000 && codePoint <= 0x1FAFF) ||
          (codePoint >= 0x2600 && codePoint <= 0x27BF) ||
          (codePoint >= 0x1F1E6 && codePoint <= 0x1F1FF);
      return !isEmojiRange && codePoint != 0xFE0F && codePoint != 0x200D;
    });
    return String.fromCharCodes(textCodePoints)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _showSmsError(String message) {
    if (!mounted) return;
    setState(() {
      _smsError = message;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _cancelAlarm() async {
    final emergencyId = _protectionService.activeEmergencyId;
    if (_isCancellingAlarm) return;
    _isCancellingAlarm = true;
    if (mounted) setState(() {});

    try {
      if (emergencyId != null) {
        if (_isGracePeriodActive) {
          await FirestoreService().cancelEmergency(emergencyId);
        } else {
          await FirestoreService().resolveEmergency(emergencyId);
        }
        _protectionService.clearActiveEmergencyId();
      }
      _gracePeriodTimer?.cancel();
      _gracePeriodEndsAt = null;
      _protectionService.clearAlarm();
      await _deactivate();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La emergencia sigue activa. Reintenta.'),
          ),
        );
      }
      debugPrint('No se pudo cerrar la emergencia: $error');
    } finally {
      _isCancellingAlarm = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _protectionService.removeListener(_onProtectionChanged);
    _gracePeriodTimer?.cancel();
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
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ShakeTrainingScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.vibration, size: 18),
                  label: const Text('PROBAR (sin enviar alerta)'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFFB300),
                  ),
                ),
              ),
              const SizedBox(height: 20),
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
                  onPressed: _protectionService.isEmergencyInProgress
                      ? null
                      : _toggleGuardia,
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
                    onPressed: _protectionService.isEmergencyInProgress
                        ? null
                        : _triggerAlarm,
                    icon: _protectionService.isEmergencyInProgress
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.warning_amber_rounded),
                    label: Text(
                      _protectionService.isEmergencyInProgress
                          ? 'ENVIANDO ALERTA...'
                          : 'ACTIVAR EMERGENCIA AHORA',
                    ),
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
                  color: const Color(0xFF1D2030),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00E6A7)),
                ),
                child: const Center(
                  child: Text(
                    'Solicitud enviada discretamente',
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
                  color: Color(0xFF00E6A7).withOpacity(0.08),
                  border: Border.all(color: Color(0xFF00E6A7), width: 3),
                ),
                child: const Center(
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 70,
                    color: Color(0xFF00E6A7),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'AYUDA SOLICITADA',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00E6A7),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              if (_smsFallbackOpened)
                const Text(
                  'Se abrió la aplicación de mensajes con el texto listo. '
                  'Revisa el destinatario y pulsa Enviar allí.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                )
              else if (_smsError != null)
                Text(
                  _smsError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              if (_isGracePeriodActive) ...[
                const SizedBox(height: 12),
                Text(
                  'Puedes cancelar la alarma en $_graceSecondsRemaining s',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
                    Expanded(
                      child: Text(
                        emergencyContact,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _smsIsOpening ? null : _prepareEmergencySms,
                  icon: _smsIsOpening
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sms_outlined),
                  label: Text(
                    _smsIsOpening
                        ? 'Abriendo mensajes…'
                        : _isGracePeriodActive
                        ? 'Abrir SMS ahora'
                        : 'Abrir mensaje SMS',
                  ),
                ),
              ),
              if (_isGracePeriodActive) const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: _isGracePeriodActive ? Colors.red : Colors.white24,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isCancellingAlarm ? null : _cancelAlarm,
                  child: Text(
                    _isCancellingAlarm
                        ? 'CANCELANDO...'
                        : _isGracePeriodActive
                        ? 'CANCELAR ALARMA'
                        : 'DESACTIVAR GUARDIA',
                    style: TextStyle(
                      color: _isGracePeriodActive ? Colors.red : Colors.white60,
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
