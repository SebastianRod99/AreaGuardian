import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

enum EmergencyActivationState { idle, submitting, active }

class _ImpactSample {
  const _ImpactSample(this.timestamp, this.amplitude);

  final DateTime timestamp;
  final double amplitude;
}

class ProtectionService extends ChangeNotifier {
  ProtectionService({
    this.onEmergencyTriggered,
    this.shakeThreshold = _defaultShakeThreshold,
    this.sustainedAccelerationThreshold =
        _defaultSustainedAccelerationThreshold,
    this.practiceMode = false,
  });

  static final ProtectionService shared = ProtectionService();

  StreamSubscription<UserAccelerometerEvent>? _userAccelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<AccelerometerEvent>? _gravitySubscription;
  Timer? _sequenceResetTimer;
  int _shakeCount = 0;
  int _shakeEventCount = 0;
  DateTime? _stableSince;
  DateTime? _activationStartedAt;
  DateTime? _sustainedMotionStartedAt;
  DateTime? _lastSustainedMotionAt;
  DateTime? _stableTiltStartedAt;
  int _sequenceGeneration = 0;
  int _protectionGeneration = 0;
  final List<_ImpactSample> _impactSamples = [];
  final List<DateTime> _motionPulseTimes = [];
  double _latestUserAcceleration = 0;
  double _latestGyroscopeMagnitude = 0;
  double? _smoothedGravityX;
  double? _smoothedGravityY;
  double? _smoothedGravityZ;
  double _gravityBaselineSumX = 0;
  double _gravityBaselineSumY = 0;
  double _gravityBaselineSumZ = 0;
  double? _gravityBaselineX;
  double? _gravityBaselineY;
  double? _gravityBaselineZ;
  int _gravityBaselineSamples = 0;
  double? _motionSignalBeforePrevious;
  double? _motionSignalPrevious;
  DateTime? _motionSignalPreviousAt;
  bool _isTriggered = false;
  bool _isDetectionArmed = true;
  bool _isProtected = false;
  bool _isPracticeComplete = false;
  EmergencyActivationState _emergencyState = EmergencyActivationState.idle;
  String? _activeEmergencyId;
  String? _shakeRejectionReason;

  static const int _requiredShakes = 4;
  static const double _defaultShakeThreshold = 15.0;
  static const double _defaultSustainedAccelerationThreshold = 2.5;
  static const Duration _resetWindow = Duration(seconds: 5);
  static const Duration _minimumShakeInterval = Duration(milliseconds: 100);
  static const Duration _rearmStabilityDuration = Duration(milliseconds: 250);
  static const Duration _sustainedMotionDuration = Duration(seconds: 10);
  static const Duration _sustainedMotionGap = Duration(milliseconds: 750);
  static const Duration _motionCadenceWindow = Duration(seconds: 8);
  static const Duration _gravityCalibrationWindow = Duration(seconds: 3);
  static const double _rearmThresholdRatio = 0.75;
  static const double _activityRearmThreshold = 1.5;
  static const double _gyroscopeActivityThreshold = 1.2;
  static const double _gyroscopeRearmThreshold = 0.6;
  static const double _stableTiltThresholdDegrees = 20.0;
  static const double _stableTiltAccelerationMaximum = 1.2;
  static const double _stableTiltGyroscopeMaximum = 0.35;
  static const double _gaitMinimumIntervalSeconds = 0.28;
  static const double _gaitMaximumIntervalSeconds = 0.9;
  static const double _gaitMaximumIntervalSpreadSeconds = 0.22;
  static const double _gaitMaximumCoefficientOfVariation = 0.20;
  static const double _gaitMaximumImpactAmplitudeRatio = 1.8;

  final double shakeThreshold;
  final double sustainedAccelerationThreshold;
  final bool practiceMode;
  double get _rearmThreshold => shakeThreshold * _rearmThresholdRatio;

  FutureOr<void> Function()? onEmergencyTriggered;

  int get shakeCount => _shakeCount;
  int get shakeEventCount => _shakeEventCount;
  double get latestAcceleration => _latestUserAcceleration;
  String? get shakeRejectionReason => _shakeRejectionReason;
  bool get isPracticeComplete => practiceMode && _isPracticeComplete;
  bool get isProtected => _isProtected;
  bool get isEmergencyInProgress =>
      _emergencyState == EmergencyActivationState.submitting;
  bool get isAlarmActive => _emergencyState == EmergencyActivationState.active;
  String? get activeEmergencyId => _activeEmergencyId;

  bool beginEmergencyActivation() {
    if (!_isProtected || _emergencyState != EmergencyActivationState.idle) {
      return false;
    }

    _emergencyState = EmergencyActivationState.submitting;
    _isTriggered = true;
    _resetShakeSequence(notify: false, resetDetectionState: true);
    notifyListeners();
    return true;
  }

  void markAlarmActive(String emergencyId) {
    _activeEmergencyId = emergencyId;
    _emergencyState = EmergencyActivationState.active;
    _isTriggered = true;
    _cancelSequenceResetTimer();
    notifyListeners();
  }

  void failEmergencyActivation() {
    if (_emergencyState != EmergencyActivationState.submitting) return;

    _emergencyState = EmergencyActivationState.idle;
    _isTriggered = false;
    _resetShakeSequence(notify: false, resetDetectionState: true);
    _resetSustainedMotion();
    notifyListeners();
  }

  void clearActiveEmergencyId() {
    _activeEmergencyId = null;
  }

  void activate({bool listen = true}) {
    if (_isProtected || _emergencyState != EmergencyActivationState.idle) {
      return;
    }
    _protectionGeneration++;
    _isProtected = true;
    _activationStartedAt = DateTime.now();
    _resetMotionCalibration();
    _resetShakeSequence(notify: false, resetDetectionState: true);
    if (listen) _startListening();
    notifyListeners();
  }

  void deactivate() {
    if (isEmergencyInProgress) return;
    _protectionGeneration++;
    _isProtected = false;
    _isTriggered = false;
    _resetShakeSequence(notify: false, resetDetectionState: true);
    _cancelSensorSubscriptions();
    _resetMotionCalibration();
    notifyListeners();
  }

  void _startListening() {
    if (_userAccelerometerSubscription != null) return;
    final protectionGeneration = _protectionGeneration;
    _userAccelerometerSubscription = userAccelerometerEventStream().listen((
      event,
    ) {
      if (protectionGeneration != _protectionGeneration) return;
      final acceleration = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      final now = DateTime.now();
      _latestUserAcceleration = acceleration;
      if (practiceMode) {
        notifyListeners();
      } else {
        handleMotionSample(
          now,
          userAcceleration: acceleration,
          gyroscopeMagnitude: _latestGyroscopeMagnitude,
          tiltDegrees: _currentTiltDegrees(),
        );
      }
      handleShakeEvent(now, acceleration);
    });
    if (practiceMode) return;

    _gyroscopeSubscription = gyroscopeEventStream().listen((event) {
      if (protectionGeneration != _protectionGeneration) return;
      final now = DateTime.now();
      _latestGyroscopeMagnitude = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      handleMotionSample(
        now,
        userAcceleration: _latestUserAcceleration,
        gyroscopeMagnitude: _latestGyroscopeMagnitude,
        tiltDegrees: _currentTiltDegrees(),
      );
    });
    _gravitySubscription = accelerometerEventStream().listen((event) {
      if (protectionGeneration != _protectionGeneration) return;
      handleGravitySample(DateTime.now(), event.x, event.y, event.z);
    });
  }

  void handleShakeEvent(DateTime now, double acceleration) {
    if (!_isProtected ||
        _emergencyState != EmergencyActivationState.idle ||
        _isTriggered ||
        _shakeCount >= _requiredShakes) {
      return;
    }

    _impactSamples.removeWhere(
      (sample) => now.difference(sample.timestamp) >= _resetWindow,
    );
    _shakeCount = _impactSamples.length;

    if (!_isDetectionArmed) {
      if (acceleration <= _rearmThreshold) {
        _stableSince ??= now;
        if (now.difference(_stableSince!) >= _rearmStabilityDuration) {
          _isDetectionArmed = true;
          _stableSince = null;
        }
      } else {
        _stableSince = null;
      }

      if (!_isDetectionArmed) return;
    }

    if (acceleration <= shakeThreshold) return;

    if (_impactSamples.isNotEmpty &&
        now.difference(_impactSamples.last.timestamp) < _minimumShakeInterval) {
      return;
    }

    _shakeRejectionReason = null;
    _impactSamples.add(_ImpactSample(now, acceleration));
    _shakeCount = _impactSamples.length;
    _scheduleSequenceReset();
    _isDetectionArmed = false;
    _stableSince = null;
    _shakeEventCount++;
    debugPrint('Sacudida detectada: $_shakeCount/$_requiredShakes');
    notifyListeners();

    if (_shakeCount == _requiredShakes) {
      if (_isLikelyLocomotionImpactPattern()) {
        debugPrint('Patrón de impacto rítmico filtrado como marcha/trote.');
        _resetShakeSequence();
        _shakeRejectionReason =
            'Parece que caminas. Agita de forma brusca.';
        notifyListeners();
        return;
      }
      _isTriggered = true;
      _cancelSequenceResetTimer();
      if (practiceMode) {
        _isPracticeComplete = true;
        notifyListeners();
        return;
      }
      unawaited(_triggerEmergency(_protectionGeneration));
      return;
    }
  }

  void handleMotionSample(
    DateTime now, {
    required double userAcceleration,
    double gyroscopeMagnitude = 0,
    double tiltDegrees = 0,
  }) {
    if (practiceMode ||
        !_isProtected ||
        _emergencyState != EmergencyActivationState.idle) {
      return;
    }

    _recordMotionSignal(
      now,
      math.max(userAcceleration, gyroscopeMagnitude * 1.5),
    );

    final hasSustainedMotion =
        userAcceleration >= sustainedAccelerationThreshold ||
        gyroscopeMagnitude >= _gyroscopeActivityThreshold;
    if (hasSustainedMotion) {
      if (_lastSustainedMotionAt != null &&
          now.difference(_lastSustainedMotionAt!) > _sustainedMotionGap) {
        _sustainedMotionStartedAt = now;
      } else {
        _sustainedMotionStartedAt ??= now;
      }
      _lastSustainedMotionAt = now;

      if (_isLikelyRhythmicLocomotion(now)) {
        _sustainedMotionStartedAt = null;
      } else if (now.difference(_sustainedMotionStartedAt!) >=
          _sustainedMotionDuration) {
        debugPrint('Movimiento sostenido irregular durante 10 s.');
        _triggerFromMotion();
        return;
      }
    } else {
      if (_lastSustainedMotionAt != null &&
          now.difference(_lastSustainedMotionAt!) > _sustainedMotionGap) {
        _resetSustainedMotion();
      }
    }

    final stableTilt =
        tiltDegrees >= _stableTiltThresholdDegrees &&
        userAcceleration <= _stableTiltAccelerationMaximum &&
        gyroscopeMagnitude <= _stableTiltGyroscopeMaximum;
    if (stableTilt) {
      _stableTiltStartedAt ??= now;
      if (now.difference(_stableTiltStartedAt!) >= _sustainedMotionDuration) {
        debugPrint('Inclinación estable superior a 20 grados durante 10 s.');
        _triggerFromMotion();
      }
    } else {
      _stableTiltStartedAt = null;
    }
  }

  void handleGravitySample(DateTime now, double x, double y, double z) {
    const smoothingFactor = 0.12;
    _smoothedGravityX = _smoothedGravityX == null
        ? x
        : _smoothedGravityX! + smoothingFactor * (x - _smoothedGravityX!);
    _smoothedGravityY = _smoothedGravityY == null
        ? y
        : _smoothedGravityY! + smoothingFactor * (y - _smoothedGravityY!);
    _smoothedGravityZ = _smoothedGravityZ == null
        ? z
        : _smoothedGravityZ! + smoothingFactor * (z - _smoothedGravityZ!);

    final activationStartedAt = _activationStartedAt;
    if (activationStartedAt != null &&
        now.difference(activationStartedAt) <= _gravityCalibrationWindow &&
        _latestUserAcceleration <= _activityRearmThreshold) {
      _gravityBaselineSumX += _smoothedGravityX!;
      _gravityBaselineSumY += _smoothedGravityY!;
      _gravityBaselineSumZ += _smoothedGravityZ!;
      _gravityBaselineSamples++;
      _gravityBaselineX = _gravityBaselineSumX / _gravityBaselineSamples;
      _gravityBaselineY = _gravityBaselineSumY / _gravityBaselineSamples;
      _gravityBaselineZ = _gravityBaselineSumZ / _gravityBaselineSamples;
    }

    handleMotionSample(
      now,
      userAcceleration: _latestUserAcceleration,
      gyroscopeMagnitude: _latestGyroscopeMagnitude,
      tiltDegrees: _currentTiltDegrees(),
    );
  }

  double _currentTiltDegrees() {
    final baselineX = _gravityBaselineX;
    final baselineY = _gravityBaselineY;
    final baselineZ = _gravityBaselineZ;
    final gravityX = _smoothedGravityX;
    final gravityY = _smoothedGravityY;
    final gravityZ = _smoothedGravityZ;
    if (baselineX == null ||
        baselineY == null ||
        baselineZ == null ||
        gravityX == null ||
        gravityY == null ||
        gravityZ == null) {
      return 0;
    }

    final baselineMagnitude = math.sqrt(
      baselineX * baselineX + baselineY * baselineY + baselineZ * baselineZ,
    );
    final gravityMagnitude = math.sqrt(
      gravityX * gravityX + gravityY * gravityY + gravityZ * gravityZ,
    );
    if (baselineMagnitude == 0 || gravityMagnitude == 0) return 0;

    final normalizedDot =
        (baselineX * gravityX + baselineY * gravityY + baselineZ * gravityZ) /
        (baselineMagnitude * gravityMagnitude);
    return math.acos(normalizedDot.clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  void _recordMotionSignal(DateTime now, double signal) {
    final previous = _motionSignalPrevious;
    final beforePrevious = _motionSignalBeforePrevious;
    if (previous != null &&
        beforePrevious != null &&
        previous >= sustainedAccelerationThreshold &&
        previous > beforePrevious &&
        previous >= signal) {
      _motionPulseTimes.add(_motionSignalPreviousAt ?? now);
    }
    _motionPulseTimes.removeWhere(
      (timestamp) => now.difference(timestamp) > _motionCadenceWindow,
    );
    _motionSignalBeforePrevious = previous;
    _motionSignalPrevious = signal;
    _motionSignalPreviousAt = now;
  }

  bool _isLikelyRhythmicLocomotion(DateTime now) {
    final recentPulses = _motionPulseTimes
        .where((timestamp) => now.difference(timestamp) <= _motionCadenceWindow)
        .toList();
    if (recentPulses.length < 7) return false;

    final intervals = <double>[];
    for (var index = 1; index < recentPulses.length; index++) {
      intervals.add(
        recentPulses[index].difference(recentPulses[index - 1]).inMicroseconds /
            Duration.microsecondsPerSecond,
      );
    }
    if (intervals.any(
      (interval) =>
          interval < _gaitMinimumIntervalSeconds ||
          interval > _gaitMaximumIntervalSeconds,
    )) {
      return false;
    }

    final mean =
        intervals.reduce((first, second) => first + second) / intervals.length;
    final variance =
        intervals
            .map((interval) => math.pow(interval - mean, 2))
            .reduce((first, second) => first + second) /
        intervals.length;
    return math.sqrt(variance) / mean <= _gaitMaximumCoefficientOfVariation;
  }

  bool _isLikelyLocomotionImpactPattern() {
    if (_impactSamples.length < _requiredShakes) return false;
    final impacts = _impactSamples.sublist(
      _impactSamples.length - _requiredShakes,
    );
    final intervals = <double>[];
    for (var index = 1; index < impacts.length; index++) {
      intervals.add(
        impacts[index].timestamp
                .difference(impacts[index - 1].timestamp)
                .inMicroseconds /
            Duration.microsecondsPerSecond,
      );
    }
    if (intervals.any(
      (interval) =>
          interval < _gaitMinimumIntervalSeconds ||
          interval > _gaitMaximumIntervalSeconds,
    )) {
      return false;
    }

    final intervalSpread =
        intervals.reduce(math.max) - intervals.reduce(math.min);
    final averageAmplitude =
        impacts
            .map((impact) => impact.amplitude)
            .reduce((first, second) => first + second) /
        impacts.length;
    return intervalSpread <= _gaitMaximumIntervalSpreadSeconds &&
        averageAmplitude < shakeThreshold * _gaitMaximumImpactAmplitudeRatio;
  }

  void _scheduleSequenceReset() {
    _cancelSequenceResetTimer();
    final generation = ++_sequenceGeneration;
    _sequenceResetTimer = Timer(_resetWindow, () {
      if (generation == _sequenceGeneration) _resetShakeSequence();
    });
  }

  void _triggerFromMotion() {
    if (practiceMode ||
        _isTriggered ||
        _emergencyState != EmergencyActivationState.idle) {
      return;
    }
    _isTriggered = true;
    _cancelSequenceResetTimer();
    unawaited(_triggerEmergency(_protectionGeneration));
  }

  void _resetSustainedMotion() {
    _sustainedMotionStartedAt = null;
    _lastSustainedMotionAt = null;
    _stableTiltStartedAt = null;
    _motionPulseTimes.clear();
    _motionSignalBeforePrevious = null;
    _motionSignalPrevious = null;
    _motionSignalPreviousAt = null;
  }

  void _resetMotionCalibration() {
    _resetSustainedMotion();
    _latestUserAcceleration = 0;
    _latestGyroscopeMagnitude = 0;
    _smoothedGravityX = null;
    _smoothedGravityY = null;
    _smoothedGravityZ = null;
    _gravityBaselineSumX = 0;
    _gravityBaselineSumY = 0;
    _gravityBaselineSumZ = 0;
    _gravityBaselineX = null;
    _gravityBaselineY = null;
    _gravityBaselineZ = null;
    _gravityBaselineSamples = 0;
  }

  void _cancelSensorSubscriptions() {
    unawaited(_userAccelerometerSubscription?.cancel());
    unawaited(_gyroscopeSubscription?.cancel());
    unawaited(_gravitySubscription?.cancel());
    _userAccelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _gravitySubscription = null;
  }

  void _resetShakeSequence({
    bool notify = true,
    bool resetDetectionState = false,
  }) {
    _cancelSequenceResetTimer();
    _shakeCount = 0;
    _impactSamples.clear();
    _shakeRejectionReason = null;
    _isPracticeComplete = false;
    if (resetDetectionState) {
      _isDetectionArmed = true;
      _stableSince = null;
    }
    if (notify) notifyListeners();
  }

  void _cancelSequenceResetTimer() {
    _sequenceResetTimer?.cancel();
    _sequenceResetTimer = null;
    _sequenceGeneration++;
  }

  Future<void> _triggerEmergency(int protectionGeneration) async {
    if (practiceMode ||
        !_isProtected ||
        _emergencyState != EmergencyActivationState.idle ||
        protectionGeneration != _protectionGeneration) {
      return;
    }
    try {
      await onEmergencyTriggered?.call();
    } catch (error) {
      debugPrint('No se pudo activar la emergencia: $error');
      return;
    }
  }

  void clearAlarm() {
    _emergencyState = EmergencyActivationState.idle;
    _isTriggered = false;
    _resetShakeSequence(notify: false, resetDetectionState: true);
    _resetMotionCalibration();
    notifyListeners();
  }

  void stopListening() {
    _protectionGeneration++;
    _cancelSensorSubscriptions();
    _resetShakeSequence(notify: false, resetDetectionState: true);
    _resetMotionCalibration();
    _isTriggered = false;
    _isProtected = false;
    _emergencyState = EmergencyActivationState.idle;
    _activeEmergencyId = null;
    notifyListeners();
  }

  void resetPractice() {
    if (!practiceMode) {
      throw StateError('resetPractice solo está disponible en modo práctica.');
    }
    _isTriggered = false;
    _resetShakeSequence(resetDetectionState: true);
    _resetMotionCalibration();
  }
}
