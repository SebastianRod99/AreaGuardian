import 'package:flutter/material.dart';

import '../services/consent_service.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, required this.onAccepted});

  final Future<void> Function() onAccepted;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _acceptedTermsAndPrivacy = false;
  bool _acceptedLocationUse = false;
  bool _allowAnalytics = false;
  bool _isSaving = false;

  Future<void> _accept() async {
    if (!_acceptedTermsAndPrivacy || !_acceptedLocationUse || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      await ConsentService().accept(analyticsConsent: _allowAnalytics);
      await widget.onAccepted();
    } catch (error) {
      debugPrint('No se pudo guardar el consentimiento: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo guardar tu consentimiento. Revisa la conexión e intenta de nuevo.',
          ),
        ),
      );
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121420),
        title: const Text('Antes de continuar'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const Icon(
              Icons.verified_user_outlined,
              size: 48,
              color: Color(0xFF00E6A7),
            ),
            const SizedBox(height: 14),
            const Text(
              'Tu seguridad y tus datos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _policySection(
              'Términos de uso',
              'AreaGuardian facilita una red comunitaria de apoyo, pero no reemplaza '
                  'a los servicios de emergencia ni garantiza una respuesta. Ante '
                  'un peligro inmediato, llama al 123.',
            ),
            _policySection(
              'Privacidad',
              'Usamos los datos de tu perfil y el contacto de emergencia para '
                  'prestar las funciones que solicitas. La ubicación asociada a '
                  'una alerta se comparte con vendedores activos cercanos y con '
                  'tu contacto de emergencia cuando se envía un SMS.',
            ),
            _policySection(
              'Uso de ubicación',
              'La ubicación se usa para mostrar tu posición, encontrar puestos '
                  'cercanos y localizar una emergencia. Puedes administrar el '
                  'permiso desde los ajustes del dispositivo.',
            ),
            CheckboxListTile(
              value: _acceptedTermsAndPrivacy,
              onChanged: _isSaving
                  ? null
                  : (value) => setState(
                      () => _acceptedTermsAndPrivacy = value ?? false,
                    ),
              activeColor: const Color(0xFF00E6A7),
              title: const Text(
                'Acepto los términos de uso y la política de privacidad.',
                style: TextStyle(color: Colors.white70),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _acceptedLocationUse,
              onChanged: _isSaving
                  ? null
                  : (value) =>
                      setState(() => _acceptedLocationUse = value ?? false),
              activeColor: const Color(0xFF00E6A7),
              title: const Text(
                'Autorizo el uso de mi ubicación para las funciones descritas.',
                style: TextStyle(color: Colors.white70),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _allowAnalytics,
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() => _allowAnalytics = value ?? false),
              activeColor: const Color(0xFF00E6A7),
              title: const Text(
                'Permitir el envío de métricas de uso y reportes de errores.',
                style: TextStyle(color: Colors.white70),
              ),
              subtitle: const Text(
                'Opcional. AreaGuardian funciona aunque no lo autorices.',
                style: TextStyle(color: Colors.white54),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed:
                    _acceptedTermsAndPrivacy && _acceptedLocationUse && !_isSaving
                    ? _accept
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00E6A7),
                  foregroundColor: const Color(0xFF121420),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Color(0xFF121420))
                    : const Text('Aceptar y continuar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _policySection(String title, String description) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2030),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }
}
