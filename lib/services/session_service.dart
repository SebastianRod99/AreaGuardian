import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
    final userSnapshot = await _getWithCacheFallback(userReference);
    if (!userSnapshot.exists) return false;

    final userData = userSnapshot.data();
    if (userData == null) return false;

    final isVendor =
        userData['isVendor'] == true || userData['role'] == 'vendor';
    final vendorSnapshot = isVendor
        ? await _getWithCacheFallback(
            _firestore.collection('vendors').doc(user.uid),
          )
        : null;
    final vendorData = vendorSnapshot?.data();
    final packageInfo = await PackageInfo.fromPlatform();

    await userReference.set({
      'lastLoginAt': FieldValue.serverTimestamp(),
      'appVersion': '${packageInfo.version}+${packageInfo.buildNumber}',
    }, SetOptions(merge: true));

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
  ) async {
    try {
      return await reference.get(const GetOptions(source: Source.server));
    } on FirebaseException catch (serverError) {
      if (!_isConnectivityError(serverError.code)) rethrow;

      final cachedSnapshot = await reference.get(
        const GetOptions(source: Source.cache),
      );
      if (cachedSnapshot.exists) return cachedSnapshot;
      rethrow;
    }
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
