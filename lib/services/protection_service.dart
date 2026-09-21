import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';

class ProtectionService extends ChangeNotifier {
  ProtectionService({this.onEmergencyTriggered, this.onConfirmationVibration});

  static final ProtectionService shared = ProtectionService();

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  int _shakeCount = 0;
  DateTime? _lastShakeTime;
  DateTime? _lastAlertTime;
  bool _isTriggered = false;
  bool _isProtected = false;
  bool _isAlarmActive = false;
  String? _activeEmergencyId;

  static const int _requiredShakes = 4;
  static const double _shakeThreshold = 15.0;
  static const Duration _resetWindow = Duration(seconds: 5);
  static const Duration _alertDebounce = Duration(seconds: 5);

  FutureOr<void> Function()? onEmergencyTriggered;
  Future<void> Function()? onConfirmationVibration;

  int get shakeCount => _shakeCount;
  bool get isProtected => _isProtected;
  bool get isAlarmActive => _isAlarmActive;
  String? get activeEmergencyId => _activeEmergencyId;

  void setActiveEmergencyId(String id) {
    _activeEmergencyId = id;
  }

  void clearActiveEmergencyId() {
    _activeEmergencyId = null;
  }

  void activate() {
    if (_isProtected) return;
    _isProtected = true;
    _shakeCount = 0;
    _lastShakeTime = null;
    _startListening();
    notifyListeners();
  }

  void deactivate() {
    _isProtected = false;
    _shakeCount = 0;
    _lastShakeTime = null;
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    notifyListeners();
  }

  void _startListening() {
    if (_accelerometerSubscription != null) return;
    _accelerometerSubscription = accelerometerEvents.listen((event) {
      final acceleration = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      handleShakeEvent(DateTime.now(), acceleration);
    });
  }

  void handleShakeEvent(DateTime now, double acceleration) {
    if (_isAlarmActive || acceleration <= _shakeThreshold) {
      return;
    }
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
    notifyListeners();

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
    notifyListeners();

    final emergencyResult = onEmergencyTriggered?.call();
    _isTriggered = false;
    if (emergencyResult is Future) await emergencyResult;

    if (onConfirmationVibration != null) {
      await onConfirmationVibration!();
    } else {
      await triggerConfirmationVibration();
    }
  }

  void markAlarmActive() {
    _isAlarmActive = true;
    _shakeCount = 0;
    notifyListeners();
  }

  void clearAlarm() {
    _isAlarmActive = false;
    _shakeCount = 0;
    notifyListeners();
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
    _isProtected = false;
    _isAlarmActive = false;
    _activeEmergencyId = null;
    notifyListeners();
  }
}
