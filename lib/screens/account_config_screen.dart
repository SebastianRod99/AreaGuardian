import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:areaguardian/screens/auth/login.dart';

// ==========================================
// PANTALLA DE PERFIL / CUENTA
// ==========================================
class AccountConfigScreen extends StatefulWidget {
  const AccountConfigScreen({super.key});

  @override
  State<AccountConfigScreen> createState() => _AccountConfigScreenState();
}

class _AccountConfigScreenState extends State<AccountConfigScreen> {
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _puestoController = TextEditingController();
  final _addressController = TextEditingController();

  String _userEmail = '';
  bool _isLoading = false;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('vendor_name') ?? '';
      _contactController.text = prefs.getString('contact') ?? '';
      _puestoController.text = prefs.getString('puesto_title') ?? '';
      _addressController.text = prefs.getString('vendor_address') ?? '';
      _userEmail = prefs.getString('user_email') ?? 'usuario@areaguardian.com';
    });
  }

  Future<void> _saveChanges() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnack('El nombre no puede estar vacío', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vendor_name', _nameController.text.trim());
    await prefs.setString('contact', _contactController.text.trim());
    await prefs.setString('puesto_title', _puestoController.text.trim());
    await prefs.setString('vendor_address', _addressController.text.trim());
    setState(() {
      _isLoading = false;
      _isSaved = true;
    });
    _showSnack('Cambios guardados correctamente');
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _isSaved = false);
  }

  // ==========================================
  // FUNCIÓN PARA SELECCIONAR CONTACTO DE LA AGENDA
  // ==========================================
  // ==========================================
  // FUNCIÓN PARA SELECCIONAR CONTACTO DE LA AGENDA
  // ==========================================
  Future<void> _pickContactFromPhone() async {
    try {
      final status = await FlutterContacts.permissions.request(
        PermissionType.read,
      );

      if (status != PermissionStatus.granted &&
          status != PermissionStatus.limited) {
        _showSnack(
          'Permiso de contactos denegado',
          isError: true,
        );
        return;
      }

      // Abrir selector de contactos y pedir directamente el teléfono
      final Contact? contact =
      await FlutterContacts.native.showPicker(
        properties: {
          ContactProperty.phone,
        },
      );

      if (contact != null) {
        if (contact.phones.isNotEmpty) {
          final String name =
              contact.displayName ?? 'Sin nombre';

          final String phone =
              contact.phones.first.number;

          setState(() {
            _contactController.text = '$name — $phone';
          });

          _showSnack('Contacto seleccionado correctamente');
        } else {
          _showSnack(
            'El contacto no tiene número registrado',
            isError: true,
          );
        }
      }
    } catch (e) {
      _showSnack(
        'Error al acceder a los contactos: $e',
        isError: true,
      );
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1D2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cerrar sesión',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          '¿Seguro que quieres cerrar sesión?',
          style: TextStyle(color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', false);

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
        isError ? Colors.redAccent : const Color(0xFF00E6A7),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _puestoController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAvatar(),
                    const SizedBox(height: 28),
                    _buildSectionTitle('Información personal'),
                    const SizedBox(height: 12),
                    _buildField(
                      controller: _nameController,
                      label: 'Nombre o apodo',
                      icon: Icons.person_outline,
                      hint: 'Ej: Carlos Cortés',
                    ),
                    const SizedBox(height: 12),

                    // ==========================================
                    // CAMPO DE CONTACTO CON BOTÓN DE AGENDA
                    // ==========================================
                    _buildContactFieldWithPicker(),

                    const SizedBox(height: 24),
                    _buildSectionTitle('Información del puesto'),
                    const SizedBox(height: 12),
                    _buildField(
                      controller: _puestoController,
                      label: 'Nombre del puesto',
                      icon: Icons.storefront_outlined,
                      hint: 'Ej: Puesto 3 - Variedades',
                    ),
                    const SizedBox(height: 12),
                    _buildField(
                      controller: _addressController,
                      label: 'Dirección o sector',
                      icon: Icons.location_on_outlined,
                      hint: 'Ej: Carrera 96H #17 (Parque Central)',
                    ),
                    const SizedBox(height: 28),
                    _buildSaveButton(),
                    const SizedBox(height: 16),
                    _buildInfoCard(),
                    const SizedBox(height: 24),
                    _buildLogoutButton(),
                    const SizedBox(height: 16),
                    _buildVersionInfo(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      color: const Color(0xFF121420),
      child: Row(
        children: [
          const Icon(Icons.cell_tower, color: Color(0xFF00E6A7), size: 22),
          const SizedBox(width: 8),
          const Text(
            'Mi Perfil',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          if (_isSaved)
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00E6A7).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check, color: Color(0xFF00E6A7), size: 14),
                  SizedBox(width: 4),
                  Text('Guardado',
                      style: TextStyle(
                          color: Color(0xFF00E6A7), fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── AVATAR ────────────────────────────────────────────────────────────────
  Widget _buildAvatar() {
    final initial = _nameController.text.isNotEmpty
        ? _nameController.text[0].toUpperCase()
        : 'U';
    return Center(
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00E6A7).withOpacity(0.12),
              border: Border.all(
                color: const Color(0xFF00E6A7).withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Color(0xFF00E6A7),
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _nameController.text.isNotEmpty
                ? _nameController.text
                : 'Sin nombre',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _userEmail,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── SECCIÓN TÍTULO ────────────────────────────────────────────────────────
  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFF00E6A7),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // ── CAMPO DE TEXTO ESTÁNDAR ───────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
            prefixIcon: Icon(icon, color: const Color(0xFF00E6A7), size: 20),
            filled: true,
            fillColor: const Color(0xFF1D2030),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Color(0xFF00E6A7), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ── CAMPO DE CONTACTO CON BOTÓN DE AGENDA INTEGRADO ──────────────────────
  Widget _buildContactFieldWithPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Contacto de emergencia',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            TextButton.icon(
              onPressed: _pickContactFromPhone,
              icon: const Icon(Icons.contacts, size: 14, color: Color(0xFF00E6A7)),
              label: const Text(
                'Elegir de la agenda',
                style: TextStyle(color: Color(0xFF00E6A7), fontSize: 11),
              ),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _contactController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Ej: Mamá — 300 123 4567',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
            prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF00E6A7), size: 20),
            filled: true,
            fillColor: const Color(0xFF1D2030),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00E6A7), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ── BOTÓN GUARDAR ─────────────────────────────────────────────────────────
  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00E6A7),
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _isLoading ? null : _saveChanges,
        child: _isLoading
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              color: Colors.black, strokeWidth: 2),
        )
            : const Text(
          'Guardar cambios',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }

  // ── TARJETA INFORMATIVA ───────────────────────────────────────────────────
  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2030),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00E6A7).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.info_outline,
                color: Color(0xFF00E6A7), size: 18),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Tu dirección se usa para marcar tu puesto en el mapa. Actualízala si cambias de ubicación.',
              style: TextStyle(
                  color: Colors.white54, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ── BOTÓN CERRAR SESIÓN ───────────────────────────────────────────────────
  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.redAccent, width: 1),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _logout,
        icon: const Icon(Icons.logout, color: Colors.redAccent, size: 18),
        label: const Text(
          'Cerrar sesión',
          style: TextStyle(
              color: Colors.redAccent, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ── VERSIÓN ───────────────────────────────────────────────────────────────
  Widget _buildVersionInfo() {
    return Center(
      child: Column(
        children: const [
          Text(
            'AreaGuardian v1.0.0',
            style: TextStyle(color: Colors.white24, fontSize: 11),
          ),
          SizedBox(height: 2),
          Text(
            'Seguridad y red para vendedores ambulantes',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ],
      ),
    );
  }
}