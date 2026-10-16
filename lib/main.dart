import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'widgets/bar_nav.dart';
import 'screens/auth/login.dart';
import 'screens/auth/register.dart';
import 'services/notification_service.dart';
import 'services/session_service.dart';
import 'services/app_telemetry_service.dart';
import 'services/consent_service.dart';
import 'screens/consent_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  // 2. Se convierte en async
  // 3. Obligatorio para asegurar la vinculación de widgets antes de inicializar servicios nativos
  WidgetsFlutterBinding.ensureInitialized();

  // 4. Inicializa la conexión con Firebase
  await Firebase.initializeApp();
  final preferences = await SharedPreferences.getInstance();
  await AppTelemetryService.initialize(
    collectionEnabled: preferences.getBool('analytics_consent') ?? false,
  );
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(AppTelemetryService.recordFatalFlutterError(details));
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(AppTelemetryService.recordFatalError(error, stackTrace));
    return false;
  };

  // 5. Registra el handler de notificaciones FCM en segundo plano.
  // Debe llamarse antes de runApp() y apuntar a una función de nivel
  // superior (definida en notification_service.dart).
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const AreaGuardianApp());
}

class AreaGuardianApp extends StatelessWidget {
  const AreaGuardianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Permite navegar (ej. al mapa) desde NotificationService, fuera del
      // árbol de widgets, cuando el usuario toca una notificación.
      navigatorKey: navigatorKey,
      title: 'AreaGuardian',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121420),
        primaryColor: const Color(0xFF00E6A7),
      ),
      home: const AuthCheckScreen(),
    );
  }
}

class AuthCheckScreen extends StatefulWidget {
  const AuthCheckScreen({super.key});

  @override
  State<AuthCheckScreen> createState() => _AuthCheckScreenState();
}

class _AuthCheckScreenState extends State<AuthCheckScreen> {
  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _isRegistered = false;
  bool _needsConsent = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    var isRegistered = false;
    var needsConsent = false;
    String? errorMessage;
    if (firebaseUser != null) {
      try {
        isRegistered = await SessionService().restoreSession(firebaseUser);
        needsConsent = !await ConsentService().hasCurrentConsent(
          userId: firebaseUser.uid,
        );
      } catch (error) {
        errorMessage = 'No se pudo restaurar tu perfil: $error';
      }
    } else {
      needsConsent = !await ConsentService().hasCurrentConsent();
    }
    if (!mounted) return;
    setState(() {
      _isLoggedIn = firebaseUser != null;
      _isRegistered = isRegistered;
      _needsConsent = needsConsent;
      _errorMessage = errorMessage;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00E6A7)),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _errorMessage = null;
                    });
                    _checkSession();
                  },
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_needsConsent) {
      return ConsentScreen(onAccepted: _checkSession);
    }

    // Logueado y registrado → Shell con nav bar
    if (_isLoggedIn && _isRegistered) {
      return const AppShell(initialIndex: 0);
    }

    // Logueado pero sin registrar puesto → registro
    if (_isLoggedIn && !_isRegistered) {
      return const Register();
    }

    // Sin sesión → login
    return const LoginScreen();
  }
}
