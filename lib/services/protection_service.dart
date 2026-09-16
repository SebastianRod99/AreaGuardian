import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

class ProtectionService {
  // Suscripción al sensor del acelerómetro
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  int _shakeCount = 0;
  DateTime? _lastShakeTime;

  // Configuración de umbrales
  static const int _requiredShakes = 4; // Número de sacudidas necesarias
  static const double _shakeThreshold = 15.0; // Fuerza mínima de la sacudida
  static const Duration _resetWindow = Duration(seconds: 5); // Tiempo máximo para completarlas

  // Callback que se ejecutará cuando se cumplan las 4 sacudidas reales
  Function()? onEmergencyTriggered;

  void startListening() {
    _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      // Calculamos la fuerza total de aceleración en los 3 ejes
      double acceleration = (event.x * event.x + event.y * event.y + event.z * event.z);

      // Si supera el umbral de movimiento brusco
      if (acceleration > (_shakeThreshold * _shakeThreshold)) {
        DateTime now = DateTime.now();

        // Si es la primera sacudida o ha pasado más del tiempo límite, reiniciamos el contador
        if (_lastShakeTime == null || now.difference(_lastShakeTime!) > _resetWindow) {
          _shakeCount = 1;
        } else {
          // Si está dentro de la ventana de tiempo, sumamos una sacudida
          _shakeCount++;
        }

        _lastShakeTime = now;
        debugPrint('Sacudida detectada: $_shakeCount/$_requiredShakes');

        // Verificamos si alcanzó las 4 sacudidas requeridas
        if (_shakeCount >= _requiredShakes) {
          _shakeCount = 0; // Reseteamos para evitar bucles
          _lastShakeTime = null;

          if (onEmergencyTriggered != null) {
            onEmergencyTriggered!(); // ¡Disparamos la emergencia!
          }
        }
      }
    });
  }

  void stopListening() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
  }
}