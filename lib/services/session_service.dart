import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'consent_service.dart';
import 'app_telemetry_service.dart';

class SessionService {
  SessionService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<bool> restoreSession(User user) async {
    final userReference = _firestore.collection('users').doc(user.uid);
    final userSnapshot = await _getWithCacheFallback(
      userReference,
      'users/{uid}',
    );
    debugPrint(
      'Session restore read users/{uid}: exists=${userSnapshot.exists}',
    );
    if (!userSnapshot.exists) return false;

    final userData = userSnapshot.data();
    if (userData == null) return false;

    final isVendor =
        userData['isVendor'] == true || userData['role'] == 'vendor';
    final vendorSnapshot = isVendor
        ? await _getWithCacheFallback(
            _firestore.collection('vendors').doc(user.uid),
            'vendors/{uid}',
          )
        : null;
    final vendorData = vendorSnapshot?.data();
    final packageInfo = await PackageInfo.fromPlatform();

    try {
      await userReference.set({
        'lastLoginAt': FieldValue.serverTimestamp(),
        'appVersion': '${packageInfo.version}+${packageInfo.buildNumber}',
      }, SetOptions(merge: true));
    } catch (error) {
      _logSessionFirestoreError('write users/{uid}', error);
      rethrow;
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('auth_uid') != user.uid) {
      final consentVersion = prefs.getString('consent_version');
      final consentUid = prefs.getString('consent_uid');
      final acceptedAt = prefs.getString('consent_accepted_at');
      final analyticsConsent = prefs.getBool('analytics_consent');
      final preserveConsent =
          consentVersion == ConsentService.currentVersion &&
          (consentUid == null || consentUid == user.uid);
      await prefs.clear();
      if (preserveConsent) {
        await prefs.setString('consent_version', consentVersion!);
        if (consentUid != null) await prefs.setString('consent_uid', consentUid);
        if (acceptedAt != null) {
          await prefs.setString('consent_accepted_at', acceptedAt);
        }
        if (analyticsConsent != null) {
          await prefs.setBool('analytics_consent', analyticsConsent);
        }
      }
    }

    final name = _stringValue(userData['name']).trim().isNotEmpty
        ? _stringValue(userData['name'])
        : user.displayName ?? '';
    final contact = _stringValue(userData['emergencyContact']);
    final consentVersion = _stringValue(userData['consentVersion']);
    if (consentVersion == ConsentService.currentVersion) {
      await prefs.setString('consent_version', consentVersion);
    }
    if (userData['analyticsConsent'] is bool) {
      final analyticsConsent = userData['analyticsConsent'] as bool;
      await prefs.setBool('analytics_consent', analyticsConsent);
      await AppTelemetryService.setConsent(analyticsConsent);
    }

    await prefs.setString('auth_uid', user.uid);
    await prefs.setString('user_id', user.uid);
    await prefs.setString('user_role', isVendor ? 'vendor' : 'client');
    await prefs.setString('user_name', name);
    await prefs.setString('vendor_name', name);
    await prefs.setBool('is_registered', true);
    await prefs.setBool('is_logged_in', true);
    await ConsentService().syncAcceptedConsent(user.uid);
    if (contact.isNotEmpty) {
      await prefs.setString('contact', contact);
    } else {
      await prefs.remove('contact');
    }

    if (isVendor) {
      final vendorName = _stringValue(vendorData?['vendorName']);
      final shopName = _stringValue(vendorData?['shopName']);
      final address = _stringValue(vendorData?['address']);
      final latitude = _doubleValue(vendorData?['latitude']);
      final longitude = _doubleValue(vendorData?['longitude']);

      await prefs.setString('vendor_id', user.uid);
      await prefs.setString(
        'vendor_name',
        vendorName.isNotEmpty ? vendorName : name,
      );
      await prefs.setString('puesto_title', shopName);
      await prefs.setString('vendor_address', address);
      await prefs.remove('client_id');
      if (latitude != null && longitude != null) {
        await prefs.setDouble('vendor_latitude', latitude);
        await prefs.setDouble('vendor_longitude', longitude);
        await prefs.setDouble('puesto_lat', latitude);
        await prefs.setDouble('puesto_lng', longitude);
      } else {
        await _removeVendorLocation(prefs);
      }
    } else {
      await prefs.setString('client_id', user.uid);
      await _removeVendorData(prefs);
    }

    return true;
  }

  Future<void> clearLocalSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getWithCacheFallback(
    DocumentReference<Map<String, dynamic>> reference,
    String path,
  ) async {
    try {
      final snapshot = await reference.get(
        const GetOptions(source: Source.server),
      );
      debugPrint(
        'Session restore read $path source=server: exists=${snapshot.exists}',
      );
      return snapshot;
    } on FirebaseException catch (serverError) {
      if (!_isConnectivityError(serverError.code)) {
        _logSessionFirestoreError('read $path source=server', serverError);
        rethrow;
      }

      debugPrint(
        'Session restore read $path source=server failed: '
        'type=${serverError.runtimeType}, code=${serverError.code}, '
        'error=$serverError',
      );
      try {
        final cachedSnapshot = await reference.get(
          const GetOptions(source: Source.cache),
        );
        debugPrint(
          'Session restore read $path source=cache: '
          'exists=${cachedSnapshot.exists}',
        );
        if (cachedSnapshot.exists) return cachedSnapshot;
      } catch (cacheError) {
        _logSessionFirestoreError('read $path source=cache', cacheError);
      }
      rethrow;
    }
  }

  void _logSessionFirestoreError(String operation, Object error) {
    final code = error is FirebaseException ? error.code : 'n/a';
    debugPrint(
      'Session restore $operation failed: '
      'type=${error.runtimeType}, code=$code, error=$error',
    );
  }

  bool _isConnectivityError(String code) {
    return code == 'unavailable' ||
        code == 'deadline-exceeded' ||
        code == 'network-request-failed' ||
        code == 'cancelled';
  }

  String _stringValue(dynamic value) => value is String ? value : '';

  double? _doubleValue(dynamic value) => value is num ? value.toDouble() : null;

  Future<void> _removeVendorLocation(SharedPreferences prefs) async {
    await prefs.remove('vendor_latitude');
    await prefs.remove('vendor_longitude');
    await prefs.remove('puesto_lat');
    await prefs.remove('puesto_lng');
  }

  Future<void> _removeVendorData(SharedPreferences prefs) async {
    await prefs.remove('vendor_id');
    await prefs.remove('puesto_title');
    await prefs.remove('vendor_address');
    await _removeVendorLocation(prefs);
  }
}
