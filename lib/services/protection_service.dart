import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';

class ProtectionService {
  ProtectionService({this.onEmergencyTriggered, this.onConfirmationVibration});

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  int _shakeCount = 0;
  DateTime? _lastShakeTime;
  DateTime? _lastAlertTime;
  bool _isTriggered = false;

  static const int _requiredShakes = 4;
  static const double _shakeThreshold = 15.0;
  static const Duration _resetWindow = Duration(seconds: 5);
  static const Duration _alertDebounce = Duration(seconds: 5);

  FutureOr<void> Function()? onEmergencyTriggered;
  Future<void> Function()? onConfirmationVibration;

  int get shakeCount => _shakeCount;

  void startListening() {
    _accelerometerSubscription = accelerometerEvents.listen((
      AccelerometerEvent event,
    ) {
      final acceleration = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );

      if (acceleration > _shakeThreshold) {
        handleShakeEvent(DateTime.now(), acceleration);
      }
    });
  }

  void handleShakeEvent(DateTime now, double acceleration) {
    if (acceleration <= _shakeThreshold) return;

    if (_lastAlertTime != null &&
        now.difference(_lastAlertTime!) < _alertDebounce) {
      return;
    }

    if (_lastShakeTime == null ||
        now.difference(_lastShakeTime!) > _resetWindow) {
      _shakeCount = 1;
    } else {
      _shakeCount++;
    }

    _lastShakeTime = now;
    debugPrint('Sacudida detectada: $_shakeCount/$_requiredShakes');

    if (_shakeCount >= _requiredShakes) {
      _lastAlertTime = now;
      _lastShakeTime = null;
      unawaited(_triggerEmergency());
    }
  }

  Future<void> _triggerEmergency() async {
    if (_isTriggered) return;
    _isTriggered = true;
    _shakeCount = 0;

    final emergencyResult = onEmergencyTriggered?.call();
    _isTriggered = false;
    if (emergencyResult is Future) {
      await emergencyResult;
    }

    if (onConfirmationVibration != null) {
      await onConfirmationVibration!();
    } else {
      await triggerConfirmationVibration();
    }
  }

  Future<void> triggerConfirmationVibration() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator ?? false) {
      await Vibration.vibrate(pattern: [0, 100, 100, 100, 100, 100]);
    }
  }

  void stopListening() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _shakeCount = 0;
    _lastShakeTime = null;
    _lastAlertTime = null;
    _isTriggered = false;
  }
}
