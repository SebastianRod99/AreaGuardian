import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencyAlertService {
  static Future<void> sendSMSAlert(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String contacto = prefs.getString('contact') ?? '';

      if (contacto.isEmpty) {
        _showSnackBar(context, 'No hay contacto de emergencia guardado',
            isError: true);
        return;
      }

      // Extraer y limpiar el número
      String numero = '';
      if (contacto.contains('—')) {
        numero = contacto.split('—').last.trim();
      } else {
        numero = contacto.trim();
      }

      numero = numero.replaceAll(RegExp(r'[^0-9]'), '');

      if (numero.startsWith('3') && numero.length == 10) {
        numero = '57$numero';
      }

      if (numero.isEmpty) {
        _showSnackBar(context, 'El número de emergencia no es válido',
            isError: true);
        return;
      }

      // Obtener ubicación GPS
      String ubicacion = 'Ubicación no disponible';
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        ubicacion =
            'https://maps.google.com/?q=${position.latitude},${position.longitude}';
      } catch (e) {
        debugPrint('ERROR GPS: $e');
      }

      // Mensaje de alerta
      final String mensaje = '🚨 ALERTA DE EMERGENCIA 🚨\n\n'
          'Necesito ayuda ahora mismo.\n\n'
          '📍 Mi ubicación actual:\n'
          '$ubicacion\n\n'
          'Enviado desde AreaGuardian';

      final String encodedMsg = Uri.encodeComponent(mensaje);

      // Intento 1 — con código de país
      final Uri smsUri = Uri.parse('sms:+$numero?body=$encodedMsg');
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
        return;
      }

      // Intento 2 — sin el +
      final Uri smsAlt = Uri.parse('sms:$numero?body=$encodedMsg');
      if (await canLaunchUrl(smsAlt)) {
        await launchUrl(smsAlt, mode: LaunchMode.externalApplication);
        return;
      }

      _showSnackBar(context, 'No se pudo abrir la app de mensajes',
          isError: true);
    } catch (e) {
      _showSnackBar(context, 'Error al enviar alerta: $e', isError: true);
    }
  }

  static void _showSnackBar(BuildContext context, String message,
      {bool isError = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.redAccent : const Color(0xFF00E6A7),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}
