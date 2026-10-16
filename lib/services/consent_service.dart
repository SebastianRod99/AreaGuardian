import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_telemetry_service.dart';

class ConsentService {
  ConsentService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String currentVersion = '1.0';
  static const String _versionKey = 'consent_version';
  static const String _acceptedAtKey = 'consent_accepted_at';
  static const String _analyticsKey = 'analytics_consent';
  static const String _uidKey = 'consent_uid';

  final FirebaseFirestore _firestore;

  Future<bool> hasCurrentConsent({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (_hasCurrentLocalConsent(prefs) &&
        (userId == null ||
            prefs.getString(_uidKey) == null ||
            prefs.getString(_uidKey) == userId)) {
      if (userId != null) {
        await syncAcceptedConsent(userId);
      }
      return true;
    }
    if (userId == null) return false;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .get(const GetOptions(source: Source.server));
      if (!snapshot.exists ||
          snapshot.data()?['consentVersion'] != currentVersion) {
        return false;
      }
      final analyticsConsent = snapshot.data()?['analyticsConsent'] == true;
      await _saveLocalConsent(
        prefs,
        userId: userId,
        analyticsConsent: analyticsConsent,
        acceptedAt: DateTime.now(),
      );
      await AppTelemetryService.setConsent(analyticsConsent);
      return true;
    } on FirebaseException catch (error) {
      if (!_isConnectivityError(error.code)) rethrow;
      final cachedSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .get(const GetOptions(source: Source.cache));
      if (cachedSnapshot.data()?['consentVersion'] != currentVersion) {
        return false;
      }
      final analyticsConsent =
          cachedSnapshot.data()?['analyticsConsent'] == true;
      await _saveLocalConsent(
        prefs,
        userId: userId,
        analyticsConsent: analyticsConsent,
        acceptedAt: DateTime.now(),
      );
      await AppTelemetryService.setConsent(analyticsConsent);
      return true;
    }
  }

  Future<void> accept({required bool analyticsConsent}) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final prefs = await SharedPreferences.getInstance();
    await _saveLocalConsent(
      prefs,
      userId: userId,
      analyticsConsent: analyticsConsent,
      acceptedAt: DateTime.now(),
    );
    await AppTelemetryService.setConsent(analyticsConsent);
    if (userId != null) await syncAcceptedConsent(userId);
  }

  Future<void> syncAcceptedConsent(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_hasCurrentLocalConsent(prefs)) return;
    final userReference = _firestore.collection('users').doc(userId);
    try {
      final userSnapshot = await userReference.get(
        const GetOptions(source: Source.server),
      );
      if (!userSnapshot.exists) return;

      await userReference.update({
        'consentVersion': currentVersion,
        'consentAcceptedAt': FieldValue.serverTimestamp(),
        'analyticsConsent': prefs.getBool(_analyticsKey) ?? false,
      });
      await prefs.setString(_uidKey, userId);
    } on FirebaseException catch (error) {
      if (!_isConnectivityError(error.code)) rethrow;
      debugPrint('El consentimiento se sincronizará al recuperar la red.');
    }
  }

  bool _hasCurrentLocalConsent(SharedPreferences prefs) =>
      prefs.getString(_versionKey) == currentVersion;

  Future<void> _saveLocalConsent(
    SharedPreferences prefs, {
    required String? userId,
    required bool analyticsConsent,
    required DateTime acceptedAt,
  }) async {
    await prefs.setString(_versionKey, currentVersion);
    await prefs.setString(_acceptedAtKey, acceptedAt.toIso8601String());
    await prefs.setBool(_analyticsKey, analyticsConsent);
    if (userId == null) {
      await prefs.remove(_uidKey);
    } else {
      await prefs.setString(_uidKey, userId);
    }
  }

  bool _isConnectivityError(String code) =>
      code == 'unavailable' ||
      code == 'deadline-exceeded' ||
      code == 'network-request-failed' ||
      code == 'cancelled';
}
