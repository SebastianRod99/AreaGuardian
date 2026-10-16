import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:areaguardian/models/emergency_model.dart';
import 'package:areaguardian/screens//user/home.dart';
import 'package:areaguardian/screens/map_dashboard_screen.dart';
import 'package:areaguardian/screens/account_config_screen.dart';
import 'package:areaguardian/screens/user/security.dart';
import 'package:areaguardian/services/firestore_service.dart';
import 'package:areaguardian/services/notification_service.dart';
import 'package:areaguardian/services/protection_service.dart';
import 'package:areaguardian/services/location_service.dart';

// ==========================================
// NAVEGACIÓN PRINCIPAL CON BOTTOM NAV BAR
// ==========================================
class AppShell extends StatefulWidget {
  final int initialIndex;
  const AppShell({super.key, this.initialIndex = 0});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static final Set<String> _shownRecoveryPrompts = {};

  late int _currentIndex;
  late DateTime _sessionStartedAt;
  String? _activeEmergencyIdAtStart;
  Timer? _pendingEmergencyTimeout;
  BuildContext? _recoveryDialogContext;

  // Pantallas del nav bar — en orden
  late final List<Widget> _screens = [
    MainScreen(
      onOpenMap: () => _onTabTapped(2),
      onOpenProfile: () => _onTabTapped(3),
    ), // 0 — Inicio / Seguridad
    const SecurityScreen(), // 1 — Seguridad dedicada
    const MapDashboardScreen(), // 2 — Mapa
    const AccountConfigScreen(), // 3 — Perfil
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _sessionStartedAt = DateTime.now();
    _activeEmergencyIdAtStart = ProtectionService.shared.activeEmergencyId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeSessionServices());
      unawaited(NotificationService().showPendingEmergencySurvey());
    });
  }

  /// Arranca, una sola vez por sesión, los servicios que deben vivir
  /// mientras el usuario está logueado — sin importar en qué pestaña esté:
  /// - Notificaciones push (todos los roles, aunque solo el vendedor recibe
  ///   alertas de emergencia por ahora).
  /// - Chequeo de proximidad dueño↔puesto (solo vendedores). Esto reemplaza
  ///   la lógica que tenía vendor_home.dart, una pantalla a la que nunca se
  ///   navegaba y por lo tanto nunca corría.
  Future<void> _initializeSessionServices() async {
    await LocationService.ensureLocationPermission();
    if (!mounted) return;
    await NotificationService().initialize();
    await _restorePendingEmergency();
  }

  Future<void> _restorePendingEmergency() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final emergency = await FirestoreService().findPendingEmergency(
        userId,
        createdBefore: _sessionStartedAt,
      );
      if (!mounted) return;

      final protectionService = ProtectionService.shared;
      if (emergency == null) {
        if (protectionService.activeEmergencyId != null &&
            protectionService.activeEmergencyId == _activeEmergencyIdAtStart) {
          protectionService.clearActiveEmergencyId();
          protectionService.clearAlarm();
          protectionService.deactivate();
        }
        return;
      }

      final alreadyActiveInSession = _activeEmergencyIdAtStart == emergency.id;
      protectionService.markAlarmActive(emergency.id);
      if (!alreadyActiveInSession ||
          _shownRecoveryPrompts.contains(emergency.id)) {
        _scheduleEmergencyTimeout(emergency);
      }

      if (alreadyActiveInSession &&
          !_shownRecoveryPrompts.contains(emergency.id)) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_shownRecoveryPrompts.add(emergency.id)) return;
        unawaited(_showRecoveryPrompt(emergency));
      });
    } catch (error) {
      debugPrint('No se pudo recuperar la emergencia pendiente: $error');
    }
  }

  void _scheduleEmergencyTimeout(EmergencyModel emergency) {
    _pendingEmergencyTimeout?.cancel();
    final expiresAt = emergency.timestamp.add(
      FirestoreService.emergencyVisibilityDuration,
    );
    final remaining = expiresAt.difference(DateTime.now());
    _pendingEmergencyTimeout = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () => unawaited(_expireRecoveredEmergency(emergency.id)),
    );
  }

  Future<void> _showRecoveryPrompt(EmergencyModel emergency) async {
    if (!mounted) return;
    final confirmation = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        _recoveryDialogContext = dialogContext;
        return AlertDialog(
          title: const Text('¿Todo estuvo bien?'),
          content: const Text('La emergencia sigue activa. ¿Quieres cerrarla?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No, mantener activa'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sí, todo bien'),
            ),
          ],
        );
      },
    );
    _recoveryDialogContext = null;

    if (confirmation == true) {
      await _resolveRecoveredEmergency(emergency.id);
    }
  }

  Future<void> _expireRecoveredEmergency(String emergencyId) async {
    if (ProtectionService.shared.activeEmergencyId != emergencyId) return;

    final resolved = await _resolveRecoveredEmergency(
      emergencyId,
      showError: false,
    );
    if (!resolved &&
        ProtectionService.shared.activeEmergencyId == emergencyId) {
      _pendingEmergencyTimeout = Timer(
        const Duration(seconds: 30),
        () => unawaited(_expireRecoveredEmergency(emergencyId)),
      );
    }

    final dialogContext = _recoveryDialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop(false);
    }
  }

  Future<bool> _resolveRecoveredEmergency(
    String emergencyId, {
    bool showError = true,
  }) async {
    try {
      await FirestoreService().resolveEmergency(emergencyId);
      final protectionService = ProtectionService.shared;
      if (protectionService.activeEmergencyId == emergencyId) {
        protectionService.clearActiveEmergencyId();
        protectionService.clearAlarm();
      }
      _pendingEmergencyTimeout?.cancel();
      return true;
    } catch (error) {
      if (showError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo cerrar la emergencia. Sigue activa.'),
          ),
        );
      }
      debugPrint('No se pudo cerrar la emergencia recuperada: $error');
      return false;
    }
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  @override
  void dispose() {
    _pendingEmergencyTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      // IndexedStack mantiene el estado de cada pantalla al cambiar de tab
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1D2030),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          backgroundColor: Colors.transparent,
          selectedItemColor: const Color(0xFF00E6A7),
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Inicio',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.security_outlined),
              activeIcon: Icon(Icons.security),
              label: 'Seguridad',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Mapa',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// WIDGET DE NAV BAR PARA USAR EN PANTALLAS
// INDIVIDUALES (sin AppShell)
// ==========================================
class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  const AppBottomNavBar({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1D2030),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) => _navigate(context, index),
        backgroundColor: Colors.transparent,
        selectedItemColor: const Color(0xFF00E6A7),
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.security_outlined),
            activeIcon: Icon(Icons.security),
            label: 'Seguridad',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, int index) {
    if (index == currentIndex) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => AppShell(initialIndex: index),
        transitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }
}
