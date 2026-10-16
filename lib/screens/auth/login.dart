import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:areaguardian/widgets/bar_nav.dart';
import 'package:areaguardian/services/auth_service.dart';
import 'package:areaguardian/services/session_service.dart';
import 'package:areaguardian/services/consent_service.dart';
import 'package:areaguardian/screens/consent_screen.dart';
import 'package:areaguardian/screens/map_dashboard_screen.dart';

import 'register.dart';

// ==========================================
// SECCIÓN DE PANTALLA DE LOGIN (SOCIAL)
// ==========================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.signInWithGoogle();
      final user = _authService.currentUser;
      if (user == null) {
        throw StateError('No se encontró la sesión de Google.');
      }
      final isRegistered = await SessionService().restoreSession(user);
      final needsConsent = !await ConsentService().hasCurrentConsent(
        userId: user.uid,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (routeContext) => needsConsent
              ? ConsentScreen(
                  onAccepted: () async {
                    Navigator.of(routeContext).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => isRegistered
                            ? const AppShell(initialIndex: 0)
                            : const Register(),
                      ),
                    );
                  },
                )
              : isRegistered
              ? const AppShell(initialIndex: 0)
              : const Register(),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message ?? error.code);
    } catch (error) {
      if (mounted)
        setState(() => _errorMessage = 'No se pudo iniciar sesión: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ==========================================
              // SECCIÓN DE LOGO E IDENTIDAD
              // ==========================================
              const Icon(Icons.cell_tower, size: 64, color: Color(0xFF00E6A7)),
              const SizedBox(height: 16),
              const Text(
                'AreaGuardian',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Seguridad y red de apoyo para vendedores ambulantes',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 50),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isLoading ? null : _signInWithGoogle,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.g_mobiledata,
                      size: 28,
                      color: Colors.black,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isLoading
                          ? 'Conectando...'
                          : 'Iniciar sesión con Google',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _isLoading
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MapDashboardScreen(),
                        ),
                      ),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Explorar el mapa sin iniciar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
