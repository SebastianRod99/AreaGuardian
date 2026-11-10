import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class AppTelemetryService {
  AppTelemetryService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static bool _collectionEnabled = false;

  static Future<void> initialize({required bool collectionEnabled}) async {
    _collectionEnabled = collectionEnabled;
    try {
      await _analytics.setAnalyticsCollectionEnabled(collectionEnabled);
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        collectionEnabled,
      );
    } catch (error, stackTrace) {
      debugPrint('No se pudo configurar la telemetría: $error\n$stackTrace');
    }
  }

  static Future<void> setConsent(bool enabled) async {
    await initialize(collectionEnabled: enabled);
  }

  static Future<void> recordFatalFlutterError(
    FlutterErrorDetails details,
  ) async {
    if (!_collectionEnabled) return;
    try {
      await FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    } catch (error, stackTrace) {
      debugPrint('No se pudo registrar el error fatal: $error\n$stackTrace');
    }
  }

  static Future<void> recordFatalError(
    Object error,
    StackTrace stackTrace,
  ) async {
    if (!_collectionEnabled) return;
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        fatal: true,
      );
    } catch (recordingError, recordingStackTrace) {
      debugPrint(
        'No se pudo registrar el error de plataforma: '
        '$recordingError\n$recordingStackTrace',
      );
    }
  }

  static Future<void> logPracticeCompleted() => _logEvent('practice_completed');

  static Future<void> logGuardActivated() => _logEvent('guard_activated');

  static Future<void> logEmergencyCreated() => _logEvent('emergency_created');

  static Future<void> logFalseAlarm() => _logEvent('false_alarm');

  static Future<void> _logEvent(String name) async {
    if (!_collectionEnabled) return;
    try {
      await _analytics.logEvent(name: name);
    } catch (error, stackTrace) {
      debugPrint('No se pudo registrar evento "$name": $error\n$stackTrace');
    }
  }
}
