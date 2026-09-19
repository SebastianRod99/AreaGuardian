import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:areaguardian/services/firestore_service.dart';
import 'package:areaguardian/services/location_service.dart';

class EmergencyAlertService {
  static Future<void> sendSMSAlert(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String contacto = prefs.getString('contact') ?? '';

      if (contacto.isEmpty) {
        _showSnackBar(
          context,
          'No hay contacto de emergencia guardado',
          isError: true,
        );
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
        _showSnackBar(
          context,
          'El número de emergencia no es válido',
          isError: true,
        );
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
      final String mensaje =
          '🚨 ALERTA DE EMERGENCIA 🚨\n\n'
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

      _showSnackBar(
        context,
        'No se pudo abrir la app de mensajes',
        isError: true,
      );
    } catch (e) {
      _showSnackBar(context, 'Error al enviar alerta: $e', isError: true);
    }
  }

  static void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF00E6A7),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

class ShakeVibrationScreen extends StatefulWidget {
  const ShakeVibrationScreen({super.key});

  @override
  State<ShakeVibrationScreen> createState() => _ShakeVibrationScreenState();
}

class _ShakeVibrationScreenState extends State<ShakeVibrationScreen> {
  StreamSubscription? _accelerometerSubscription;

  int _shakeCount = 0;
  DateTime? _lastShakeTime;
  DateTime? _lastAlertTime;

  // Umbral de fuerza para considerar que se ha "agitado" el teléfono
  final double _shakeThreshold = 15.0;

  @override
  void initState() {
    super.initState();
    _startListeningSensors();
  }

  void _startListeningSensors() {
    _accelerometerSubscription = accelerometerEvents.listen((
      AccelerometerEvent event,
    ) {
      // Calculamos la fuerza total de la aceleración en los 3 ejes (X, Y, Z)
      double acceleration = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );

      // Si la fuerza supera el umbral configurado
      if (acceleration > _shakeThreshold) {
        final now = DateTime.now();
        if (_lastAlertTime != null &&
            now.difference(_lastAlertTime!) < const Duration(seconds: 5)) {
          return;
        }

        // Si es la primera sacudida o ha pasado poco tiempo desde la última (ej. menos de 800ms)
        if (_lastShakeTime == null ||
            now.difference(_lastShakeTime!) <
                const Duration(milliseconds: 800)) {
          _shakeCount++;
          _lastShakeTime = now;

          // Si llega a 4 sacudidas
          if (_shakeCount >= 4) {
            _onFourShakeDetected();
            _shakeCount = 0; // Reiniciamos el contador
            _lastShakeTime = null;
          }
        } else {
          // Si pasó mucho tiempo entre sacudidas, reiniciamos el conteo
          _shakeCount = 1;
          _lastShakeTime = now;
        }
      }
    });
  }

  // ACCIÓN AL COMPLETAR LAS 4 SACUDIDAS
  void _onFourShakeDetected() async {
    debugPrint("¡Se detectaron 4 sacudidas!");

    final prefs = await SharedPreferences.getInstance();
    final position = await LocationService().getCurrentLocationForEmergency();
    if (position == null) return;
    await FirestoreService().createEmergency(
      userId: prefs.getString('user_id') ?? prefs.getString('client_id') ?? '',
      userName:
          prefs.getString('user_name') ??
          prefs.getString('vendor_name') ??
          'Usuario AreaGuardian',
      latitude: position.latitude,
      longitude: position.longitude,
    );
    _lastAlertTime = DateTime.now();

    if (await Vibration.hasVibrator() ?? false) {
      await Vibration.vibrate(pattern: [0, 100, 100, 100, 100, 100]);
    }

    // 2. Aquí puedes disparar tu función de alerta (ej: EmergencyAlertService.sendAlert(context))
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚨 ¡4 sacudidas detectadas! Vibrando y alertando...'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  void dispose() {
    // Es muy importante cancelar la suscripción al cerrar la pantalla para evitar fugas de memoria
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detector de Sacudidas')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Agita tu celular 4 veces rápidamente para activar la vibración de emergencia.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
