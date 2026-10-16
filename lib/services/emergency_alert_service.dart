import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../models/emergency_model.dart';
import 'firestore_service.dart';
import 'location_service.dart';

export 'protection_service.dart';

class EmergencyAlertService {
  EmergencyAlertService({
    LocationService? locationService,
    FirestoreService? firestoreService,
  }) : _locationService = locationService ?? LocationService(),
       _firestoreService = firestoreService ?? FirestoreService();

  final LocationService _locationService;
  final FirestoreService _firestoreService;

  Future<void> vibrateConfirmation() async {
    try {
      await Vibration.vibrate(pattern: const [0, 300, 200, 300, 200, 300]);
    } catch (error) {
      debugPrint('No se pudo ejecutar la vibración de emergencia: $error');
    }
  }

  Future<EmergencyModel?> createEmergency({
    bool persist = true,
    bool isTest = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final position = await _locationService
        .getCurrentLocationForEmergency()
        .timeout(const Duration(seconds: 15), onTimeout: () => null);
    if (position == null) return null;

    final role = prefs.getString('user_role') == 'vendor' ? 'vendor' : 'client';
    final shopName = role == 'vendor'
        ? (prefs.getString('puesto_title') ?? 'Puesto comercial')
        : 'Vecino';
    final emergency = EmergencyModel(
      id: '',
      userId:
          FirebaseAuth.instance.currentUser?.uid ??
          prefs.getString('user_id') ??
          prefs.getString('client_id') ??
          '',
      userName:
          prefs.getString('user_name') ??
          prefs.getString('vendor_name') ??
          'Usuario AreaGuardian',
      role: role,
      shopName: shopName,
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: DateTime.now(),
      isTest: isTest,
    );

    if (!persist) return _asLocalEmergency(emergency);

    try {
      return await _firestoreService.saveEmergency(emergency);
    } on FirebaseException catch (error) {
      if (!{
        'unavailable',
        'deadline-exceeded',
        'network-request-failed',
      }.contains(error.code)) {
        rethrow;
      }
      debugPrint(
        'No se pudo guardar la emergencia por falta de red; '
        'se abrirá el SMS manual: ${error.code}',
      );
      return _asLocalEmergency(emergency);
    }
  }

  EmergencyModel _asLocalEmergency(EmergencyModel emergency) {
    final timestamp = DateTime.now();
    return EmergencyModel(
      id: 'offline_${emergency.userId}_${timestamp.microsecondsSinceEpoch}',
      userId: emergency.userId,
      userName: emergency.userName,
      role: emergency.role,
      shopName: emergency.shopName,
      latitude: emergency.latitude,
      longitude: emergency.longitude,
      timestamp: timestamp,
      status: emergency.status,
      smsStatus: 'failed',
    );
  }
}
