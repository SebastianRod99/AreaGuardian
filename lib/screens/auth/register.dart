import 'package:areaguardian/screens/map_dashboard_screen.dart' show MapDashboardScreen;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


// ==========================================
// SECCIÓN DE REGISTRO DE DATOS DEL VENDEDOR
// ==========================================
class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  final _nameController = TextEditingController();
  final _puestoController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isLoading = false;

  // Guarda la información del puesto y marca el registro como completado
  Future<void> _completeRegistration() async {
    if (_nameController.text.trim().isEmpty || _addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa los campos obligatorios')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vendor_name', _nameController.text.trim());
    await prefs.setString('puesto_title', _puestoController.text.trim().isEmpty ? 'Mi Puesto' : _puestoController.text.trim());
    await prefs.setString('vendor_address', _addressController.text.trim());

    // Bandera para indicar que ya completó su registro inicial
    await prefs.setBool('is_registered', true);

    if (!mounted) return;

    // Redirigimos al mapa con el puesto activo
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MapDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Registro de Puesto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ==========================================
              // SECCIÓN DE ICONO Y TÍTULO INFORMATIVO
              // ==========================================
              const Icon(Icons.storefront, size: 56, color: Color(0xFF00E6A7)),
              const SizedBox(height: 16),
              const Text(
                'Configura tu Ubicación',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 6),
              const Text(
                'Ingresa los datos de tu puesto para que la red de apoyo en Fontibón te ubique.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 30),

              // ==========================================
              // SECCIÓN DE ENTRADA: NOMBRE DEL VENDEDOR
              // ==========================================
              const Text('Tu Nombre o Apodo', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ej: Carlos Cortés',
                  hintStyle: const TextStyle(color: Colors.white24),
                  prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF00E6A7)),
                  filled: true,
                  fillColor: const Color(0xFF1D2030),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),

              // ==========================================
              // SECCIÓN DE ENTRADA: NOMBRE DEL PUESTO
              // ==========================================
              const Text('Nombre del Puesto', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _puestoController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ej: Puesto 3 - Variedades',
                  hintStyle: const TextStyle(color: Colors.white24),
                  prefixIcon: const Icon(Icons.store, color: Color(0xFF00E6A7)),
                  filled: true,
                  fillColor: const Color(0xFF1D2030),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),

              // ==========================================
              // SECCIÓN DE ENTRADA: DIRECCIÓN O SECTOR
              // ==========================================
              const Text('Dirección o Sector', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _addressController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ej: Carrera 96H #17 (Parque Central)',
                  hintStyle: const TextStyle(color: Colors.white24),
                  prefixIcon: const Icon(Icons.location_on_outlined, color: Color(0xFF00E6A7)),
                  filled: true,
                  fillColor: const Color(0xFF1D2030),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 30),

              // ==========================================
              // SECCIÓN DE BOTÓN GUARDAR Y CONTINUAR
              // ==========================================
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E6A7),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _completeRegistration,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text('Guardar y Activar Puesto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}