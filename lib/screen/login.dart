import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'map_dashboard.dart';
import 'register.dart';

// ==========================================
// SECCIÓN DE PANTALLA DE LOGIN (SOCIAL)
// ==========================================
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  // Simula el proceso de autenticación con Google o Apple
  Future<void> _handleSocialLogin(BuildContext context, String provider) async {
    final prefs = await SharedPreferences.getInstance();

    // Marcamos que el usuario ya inició sesión
    await prefs.setBool('is_logged_in', true);

    // Verificamos si ya tiene un puesto registrado previamente
    bool isRegistered = prefs.getBool('is_registered') ?? false;

    if (!context.mounted) return;

    if (isRegistered) {
      // Si ya está registrado, va directo al mapa con su puesto activo
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MapDashboardScreen()),
      );
    } else {
      // Si es su primera vez, lo enviamos a registrar los datos de su puesto
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const Register()),
      );
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
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Seguridad y red de apoyo para vendedores ambulantes',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 50),

              // ==========================================
              // SECCIÓN DE BOTÓN GOOGLE
              // ==========================================
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _handleSocialLogin(context, 'Google'),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.g_mobiledata, size: 28, color: Colors.black),
                    SizedBox(width: 8),
                    Text('Continuar con Google', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ==========================================
              // SECCIÓN DE BOTÓN APPLE
              // ==========================================
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
                onPressed: () => _handleSocialLogin(context, 'Apple'),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.apple, size: 26, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Continuar con Apple', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}