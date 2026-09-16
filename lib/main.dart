import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // 1. Importa Firebase Core
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/bar_nav.dart';
import 'screens/auth/login.dart';
import 'screens/auth/register.dart';

void main() async { // 2. Se convierte en async
  // 3. Obligatorio para asegurar la vinculación de widgets antes de inicializar servicios nativos
  WidgetsFlutterBinding.ensureInitialized();

  // 4. Inicializa la conexión con Firebase
  await Firebase.initializeApp();

  runApp(const AreaGuardianApp());
}

class AreaGuardianApp extends StatelessWidget {
  const AreaGuardianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      _isRegistered = prefs.getBool('is_registered') ?? false;
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