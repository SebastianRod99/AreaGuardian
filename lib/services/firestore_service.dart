import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;

import '../models/vendor_model.dart';
import '../models/emergency_model.dart';
import '../models/user_model.dart';
import 'app_telemetry_service.dart';
import '../utils/geo_utils.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const Duration emergencyVisibilityDuration = Duration(minutes: 20);
  static const Duration _emergencySurveyDelay = Duration(minutes: 10);
  static const Duration _emergencyCancellationGrace = Duration(seconds: 20);
  static const double emergencyAlertRadiusMeters = 300;

  Future<void> updateUserCurrentLocation({
    required double latitude,
    required double longitude,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Debes iniciar sesión para actualizar tu ubicación.');
    }
    await _db.collection('users').doc(user.uid).update({
      'lastKnownLatitude': latitude,
      'lastKnownLongitude': longitude,
      'lastKnownLocationAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveUserProfile(UserModel user) async {
    final authenticatedUser = FirebaseAuth.instance.currentUser;
    if (authenticatedUser == null || authenticatedUser.uid != user.id) {
      throw StateError('El perfil debe pertenecer al usuario autenticado.');
    }
    try {
      final userReference = _db.collection('users').doc(user.id);
      await _db.runTransaction<void>((transaction) async {
        final snapshot = await transaction.get(userReference);
        if (snapshot.exists) {
          throw StateError('El perfil ya existe; no se sobrescribió.');
        }
        transaction.set(userReference, user.toJson());
      });
    } catch (e) {
      debugPrint('Error al guardar el perfil del usuario: $e');
      rethrow;
    }
  }

  Future<void> updateEmergencyContact(String contact) async {
    final authenticatedUser = FirebaseAuth.instance.currentUser;
    if (authenticatedUser == null) {
      throw StateError('Debes iniciar sesión para guardar el contacto.');
    }
    await _db.collection('users').doc(authenticatedUser.uid).update({
      'emergencyContact': contact.trim(),
    });
  }

  Future<void> updateUserFcmToken({
    required String userId,
    required String fcmToken,
  }) async {
    final authenticatedUser = FirebaseAuth.instance.currentUser;
    if (authenticatedUser == null || authenticatedUser.uid != userId) {
      throw StateError('Solo el usuario autenticado puede registrar su token.');
    }
    await _db.collection('users').doc(userId).update({'fcmToken': fcmToken});
  }

  Future<void> submitEmergencySurvey({
    required String emergencyId,
    required bool wasSafe,
    bool? falseAlarm,
    bool? receivedHelp,
    String? details,
  }) async {
    final authenticatedUser = FirebaseAuth.instance.currentUser;
    if (authenticatedUser == null) {
      throw StateError('Debes iniciar sesión para responder la encuesta.');
    }
    if (wasSafe && falseAlarm == null) {
      throw ArgumentError('Indica si fue una falsa alarma.');
    }
    if (!wasSafe && receivedHelp == null) {
      throw ArgumentError('Indica si recibiste ayuda.');
    }
    if (!wasSafe &&
        receivedHelp == false &&
        (details?.trim().isEmpty ?? true)) {
      throw ArgumentError('Escribe los detalles antes de enviar.');
    }

    final emergencyRef = _db.collection('emergencies').doc(emergencyId);
    final userRef = _db.collection('users').doc(authenticatedUser.uid);
    await _db.runTransaction<void>((transaction) async {
      final emergencySnapshot = await transaction.get(emergencyRef);
      final userSnapshot = await transaction.get(userRef);
      if (!emergencySnapshot.exists ||
          emergencySnapshot.data()?['userId'] != authenticatedUser.uid) {
        throw StateError('La emergencia no pertenece al usuario autenticado.');
      }
      if (emergencySnapshot.data()?['surveyFeedback'] != null) {
        throw StateError('Esta encuesta ya fue respondida.');
      }

      final feedback = <String, dynamic>{
        'wasSafe': wasSafe,
        'submittedAt': FieldValue.serverTimestamp(),
      };
      if (wasSafe) {
        feedback['falseAlarm'] = falseAlarm;
      } else {
        feedback['receivedHelp'] = receivedHelp;
        if (receivedHelp == false) feedback['details'] = details!.trim();
      }

      final emergencyUpdates = <String, dynamic>{'surveyFeedback': feedback};
      if (wasSafe && falseAlarm == true) {
        emergencyUpdates['status'] = 'false_alarm';
        emergencyUpdates['resolvedAt'] = FieldValue.serverTimestamp();
        if (userSnapshot.data()?['activeEmergencyId'] == emergencyId) {
          transaction.update(userRef, {
            'activeEmergencyId': FieldValue.delete(),
          });
        }
      }
      transaction.update(emergencyRef, emergencyUpdates);
    });
    if (wasSafe && falseAlarm == true) {
      await AppTelemetryService.logFalseAlarm();
    }
  }

  /// 1. Guarda o actualiza el perfil completo del vendedor (Puesto Fijo + Estado Inicial)
  Future<void> saveVendorProfile(VendorModel vendor) async {
    final authenticatedUser = FirebaseAuth.instance.currentUser;
    if (authenticatedUser == null ||
        authenticatedUser.uid != vendor.userId ||
        vendor.id != vendor.userId) {
      throw ArgumentError(
        'El puesto debe usar el mismo ID que su propietario.',
      );
    }
    try {
      final vendorReference = _db.collection('vendors').doc(vendor.id);
      await _db.runTransaction<void>((transaction) async {
        final vendorSnapshot = await transaction.get(vendorReference);
        final existingData = vendorSnapshot.data() ?? {};
        final vendorData = vendor.toJson();
        for (final field in [
          'isActive',
          'nequiNumber',
          'daviplataNumber',
          'llaveNumber',
          'catalog',
        ]) {
          if (existingData.containsKey(field)) {
            vendorData[field] = existingData[field];
          }
        }

        final identity = {
          'id': vendor.id,
          'userId': vendor.userId,
          'shopName': vendor.shopName,
          'address': vendor.address,
          'vendorName': vendor.vendorName,
          'category': vendor.category,
          'latitude': vendor.latitude,
          'longitude': vendor.longitude,
        };
        transaction.set(
          vendorReference,
          vendorSnapshot.exists ? identity : vendorData,
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      debugPrint('Error al guardar el perfil del vendedor: $e');
      rethrow;
    }
  }

  /// 2. Obtiene la lista de todos los puestos de la red
  Future<List<VendorModel>> fetchNearbyVendors() async {
    try {
      QuerySnapshot snapshot = await _db.collection('public_vendors').get();

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = data['id'] ?? doc.id;
        return VendorModel.fromJson(data);
      }).toList();
    } catch (e) {
      debugPrint('Error al consultar puestos en Firestore: $e');
      return [];
    }
  }

  Stream<List<VendorModel>> watchPublicVendors() {
    return _db.collection('public_vendors').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = data['id'] ?? doc.id;
        return VendorModel.fromJson(data);
      }).toList();
    });
  }

  Future<void> setVendorActive({
    required String vendorId,
    required bool isActive,
  }) async {
    final authenticatedUser = FirebaseAuth.instance.currentUser;
    if (authenticatedUser == null || authenticatedUser.uid != vendorId) {
      throw StateError(
        'Solo el propietario autenticado puede activar el puesto.',
      );
    }
    await _db.collection('vendors').doc(vendorId).update({
      'isActive': isActive,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateVendorCurrentLocation({
    required String vendorId,
    required double latitude,
    required double longitude,
  }) async {
    final authenticatedUser = FirebaseAuth.instance.currentUser;
    if (authenticatedUser == null || authenticatedUser.uid != vendorId) {
      throw StateError(
        'Solo el propietario autenticado puede actualizar su ubicación.',
      );
    }
    await _db.collection('vendors').doc(vendorId).update({
      'currentLatitude': latitude,
      'currentLongitude': longitude,
      'lastLocationUpdate': FieldValue.serverTimestamp(),
    });
  }

  Future<VendorModel?> getVendor(String vendorId) async {
    final snapshot = await _db.collection('vendors').doc(vendorId).get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    final data = snapshot.data()!..['id'] = snapshot.id;
    return VendorModel.fromJson(data);
  }

  Stream<VendorModel?> watchVendor(String vendorId) {
    return _db.collection('vendors').doc(vendorId).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return null;
      final data = snapshot.data()!..['id'] = snapshot.id;
      return VendorModel.fromJson(data);
    });
  }

  Future<void> updateVendorFixedLocation({
    required String vendorId,
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    final authenticatedUser = FirebaseAuth.instance.currentUser;
    if (authenticatedUser == null || authenticatedUser.uid != vendorId) {
      throw StateError(
        'Solo el propietario autenticado puede actualizar el puesto.',
      );
    }
    final updates = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
    };
    if (address != null) updates['address'] = address;
    await _db.collection('vendors').doc(vendorId).update(updates);
  }

  Future<void> updateVendorAddress({
    required String vendorId,
    required String address,
  }) async {
    final authenticatedUser = FirebaseAuth.instance.currentUser;
    if (authenticatedUser == null || authenticatedUser.uid != vendorId) {
      throw StateError(
        'Solo el propietario autenticado puede actualizar el puesto.',
      );
    }
    await _db.collection('vendors').doc(vendorId).update({'address': address});
  }

  Future<void> updateVendorProfile({
    required String vendorId,
    required String shopName,
    required String address,
    required String nequiNumber,
    required String daviplataNumber,
    required String llaveNumber,
    required List<String> catalog,
  }) async {
    final authenticatedUser = FirebaseAuth.instance.currentUser;
    if (authenticatedUser == null || authenticatedUser.uid != vendorId) {
      throw StateError(
        'Solo el propietario autenticado puede editar el puesto.',
      );
    }
    final updates = <String, dynamic>{
      'shopName': shopName,
      'address': address,
      'nequiNumber': nequiNumber,
      'daviplataNumber': daviplataNumber,
      'llaveNumber': llaveNumber,
      'catalog': catalog,
    };
    await _db
        .collection('vendors')
        .doc(vendorId)
        .set(updates, SetOptions(merge: true));
  }

  Future<List<EmergencyModel>> fetchActiveEmergencies({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final snapshot = await _nearbyEmergencyQuery(latitude, longitude).get();
      return snapshot.docs
          .map((doc) {
            final data = doc.data();
            data['id'] = data['id'] ?? doc.id;
            return EmergencyModel.fromJson(data);
          })
          .where(
            (emergency) =>
                _isVisibleEmergency(emergency) &&
                _isWithinEmergencyRadius(emergency, latitude, longitude),
          )
          .toList();
    } catch (error) {
      debugPrint('Error al consultar emergencias cercanas: $error');
      rethrow;
    }
  }

  Future<EmergencyModel?> fetchCurrentUserActiveEmergency() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final userSnapshot = await _db.collection('users').doc(user.uid).get();
    final emergencyId = userSnapshot.data()?['activeEmergencyId'];
    if (emergencyId is! String || emergencyId.isEmpty) return null;

    final emergencySnapshot = await _db
        .collection('emergencies')
        .doc(emergencyId)
        .get();
    final data = emergencySnapshot.data();
    if (!emergencySnapshot.exists ||
        data == null ||
        data['userId'] != user.uid ||
        data['status'] != 'active') {
      return null;
    }
    data['id'] = data['id'] ?? emergencySnapshot.id;
    return EmergencyModel.fromJson(data);
  }

  Future<String?> fetchEmergencySmsStatus(String emergencyId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Debes iniciar sesión para consultar el SMS.');
    }
    final snapshot = await _db
        .collection('emergencies')
        .doc(emergencyId)
        .get(const GetOptions(source: Source.server));
    if (!snapshot.exists || snapshot.data()?['userId'] != user.uid) {
      return null;
    }
    final status = snapshot.data()?['smsStatus'];
    return status is String ? status : null;
  }

  Stream<List<EmergencyModel>> watchActiveEmergencies({
    required double latitude,
    required double longitude,
  }) {
    return _nearbyEmergencyQuery(latitude, longitude)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) {
                final data = doc.data();
                data['id'] = data['id'] ?? doc.id;
                return EmergencyModel.fromJson(data);
              })
              .where(
                (emergency) =>
                    _isVisibleEmergency(emergency) &&
                    _isWithinEmergencyRadius(emergency, latitude, longitude),
              )
              .toList(),
        );
  }

  Query<Map<String, dynamic>> _nearbyEmergencyQuery(
    double latitude,
    double longitude,
  ) {
    final latitudeDelta = emergencyAlertRadiusMeters / 111320;
    final longitudeScale = math.cos(latitude * math.pi / 180).abs();
    final longitudeDelta =
        emergencyAlertRadiusMeters / (111320 * math.max(longitudeScale, 0.01));
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(emergencyVisibilityDuration),
    );

    return _db
        .collection('emergencies')
        .where('status', isEqualTo: 'active')
        .where('isTest', isEqualTo: false)
        .where('timestamp', isGreaterThanOrEqualTo: cutoff)
        .where('latitude', isGreaterThanOrEqualTo: latitude - latitudeDelta)
        .where('latitude', isLessThanOrEqualTo: latitude + latitudeDelta)
        .where('longitude', isGreaterThanOrEqualTo: longitude - longitudeDelta)
        .where('longitude', isLessThanOrEqualTo: longitude + longitudeDelta);
  }

  bool _isWithinEmergencyRadius(
    EmergencyModel emergency,
    double latitude,
    double longitude,
  ) {
    return isWithinRadiusMeters(
      latitudeA: latitude,
      longitudeA: longitude,
      latitudeB: emergency.latitude,
      longitudeB: emergency.longitude,
      radiusMeters: emergencyAlertRadiusMeters,
    );
  }

  bool _isVisibleEmergency(EmergencyModel emergency) {
    return DateTime.now().difference(emergency.timestamp) <
        emergencyVisibilityDuration;
  }

  Future<EmergencyModel?> findPendingEmergency(
    String userId, {
    required DateTime createdBefore,
  }) async {
    final snapshot = await _db
        .collection('emergencies')
        .where('userId', isEqualTo: userId)
        .get();
    final activeEmergencies = snapshot.docs
        .where((doc) => doc.data()['status'] == 'active')
        .map((doc) {
          final data = doc.data();
          data['id'] = data['id'] ?? doc.id;
          return EmergencyModel.fromJson(data);
        })
        .where((emergency) => emergency.timestamp.isBefore(createdBefore))
        .toList();
    activeEmergencies.sort(
      (first, second) => second.timestamp.compareTo(first.timestamp),
    );

    EmergencyModel? pendingEmergency;
    for (final emergency in activeEmergencies) {
      if (_isVisibleEmergency(emergency)) {
        pendingEmergency = emergency;
        break;
      }
    }

    final staleOrDuplicateIds = activeEmergencies
        .where((emergency) => emergency.id != pendingEmergency?.id)
        .map((emergency) => emergency.id);
    await Future.wait(staleOrDuplicateIds.map(resolveEmergency));

    if (pendingEmergency == null) return null;
    return _adoptPendingEmergency(userId, pendingEmergency);
  }

  Future<EmergencyModel?> _adoptPendingEmergency(
    String userId,
    EmergencyModel candidate,
  ) async {
    final userRef = _db.collection('users').doc(userId);
    final candidateRef = _db.collection('emergencies').doc(candidate.id);

    final adopted = await _db.runTransaction<EmergencyModel?>((
      transaction,
    ) async {
      final userSnapshot = await transaction.get(userRef);
      final candidateSnapshot = await transaction.get(candidateRef);
      if (!userSnapshot.exists ||
          !candidateSnapshot.exists ||
          candidateSnapshot.data()?['status'] != 'active') {
        return null;
      }

      final currentEmergencyId =
          userSnapshot.data()?['activeEmergencyId'] as String?;
      if (currentEmergencyId != null &&
          currentEmergencyId.isNotEmpty &&
          currentEmergencyId != candidate.id) {
        final currentRef = _db
            .collection('emergencies')
            .doc(currentEmergencyId);
        final currentSnapshot = await transaction.get(currentRef);
        final currentData = currentSnapshot.data();
        if (currentSnapshot.exists &&
            currentData?['userId'] == userId &&
            currentData?['status'] == 'active') {
          final data = currentData!..['id'] = currentSnapshot.id;
          final currentEmergency = EmergencyModel.fromJson(data);
          if (_isVisibleEmergency(currentEmergency)) {
            return currentEmergency;
          }
          transaction.update(currentRef, {
            'status': 'resolved',
            'resolvedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      if (currentEmergencyId != candidate.id) {
        transaction.update(userRef, {'activeEmergencyId': candidate.id});
      }
      return candidate;
    });

    if (adopted != null && adopted.id != candidate.id) {
      await resolveEmergency(candidate.id);
    }
    return adopted;
  }

  Future<String?> findPendingEmergencySurvey(String userId) async {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    final snapshot = await _db
        .collection('emergencies')
        .where('userId', isEqualTo: userId)
        .get();
    final pendingSurveys = snapshot.docs.where((doc) {
      final emergency = doc.data();
      final timestamp = emergency['timestamp'];
      final createdAt = timestamp is Timestamp ? timestamp.toDate() : null;
      final resolvedAt = emergency['resolvedAt'];
      final cancelledAt = resolvedAt is Timestamp
          ? resolvedAt.toDate()
          : null;
      final surveyStatus = emergency['surveyNotificationStatus'];
      return emergency['isTest'] != true &&
          !_wasCancelledDuringGrace(
            status: emergency['status'],
            createdAt: createdAt,
            cancelledAt: cancelledAt,
          ) &&
          emergency['surveyFeedback'] == null &&
          (surveyStatus == 'pending' || surveyStatus == 'failed') &&
          createdAt != null &&
          !createdAt.isAfter(cutoff);
    }).toList()..sort((a, b) {
      final timestampA = a.data()['timestamp'] as Timestamp;
      final timestampB = b.data()['timestamp'] as Timestamp;
      return timestampA.compareTo(timestampB);
    });
    return pendingSurveys.isEmpty ? null : pendingSurveys.first.id;
  }

  Future<bool> canShowEmergencySurvey(String emergencyId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final snapshot = await _db
        .collection('emergencies')
        .doc(emergencyId)
        .get();
    if (!snapshot.exists) return false;

    final emergency = snapshot.data()!;
    final timestamp = emergency['timestamp'];
    final createdAt = timestamp is Timestamp ? timestamp.toDate() : null;
    final resolvedAt = emergency['resolvedAt'];
    final cancelledAt = resolvedAt is Timestamp
        ? resolvedAt.toDate()
        : null;
    return emergency['userId'] == user.uid &&
        emergency['isTest'] != true &&
        !_wasCancelledDuringGrace(
          status: emergency['status'],
          createdAt: createdAt,
          cancelledAt: cancelledAt,
        ) &&
        emergency['surveyFeedback'] == null &&
        createdAt != null &&
        !createdAt
            .add(_emergencySurveyDelay)
            .isAfter(DateTime.now());
  }

  bool _wasCancelledDuringGrace({
    required Object? status,
    required DateTime? createdAt,
    required DateTime? cancelledAt,
  }) {
    return status == 'cancelled' &&
        createdAt != null &&
        cancelledAt != null &&
        !cancelledAt.isAfter(
          createdAt.add(_emergencyCancellationGrace),
        );
  }

  Future<void> resolveEmergency(String emergencyId) async {
    await _closeEmergency(emergencyId, 'resolved');
  }

  Future<void> cancelEmergency(String emergencyId) async {
    await _closeEmergency(emergencyId, 'cancelled');
  }

  Future<void> _closeEmergency(String emergencyId, String finalStatus) async {
    final emergencyRef = _db.collection('emergencies').doc(emergencyId);
    await _db.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(emergencyRef);
      if (!snapshot.exists) return;

      final emergency = snapshot.data()!;
      final userRef = _db
          .collection('users')
          .doc(emergency['userId'] as String);
      final userSnapshot = await transaction.get(userRef);

      if (emergency['status'] == 'active') {
        transaction.update(emergencyRef, {
          'status': finalStatus,
          'resolvedAt': FieldValue.serverTimestamp(),
        });
      }
      if (userSnapshot.data()?['activeEmergencyId'] == emergencyId) {
        transaction.update(userRef, {'activeEmergencyId': FieldValue.delete()});
      }
    });
  }

  Future<EmergencyModel> saveEmergency(EmergencyModel emergency) async {
    final authenticatedUser = FirebaseAuth.instance.currentUser;
    if (authenticatedUser == null ||
        authenticatedUser.uid != emergency.userId) {
      throw StateError(
        'Debes iniciar sesión con Google para crear una alerta.',
      );
    }
    if (emergency.role != 'vendor' && emergency.role != 'client') {
      throw ArgumentError('El rol de la emergencia no es válido.');
    }
    final normalizedShopName = emergency.role == 'vendor'
        ? emergency.shopName.trim()
        : 'Vecino';
    if (normalizedShopName.isEmpty) {
      throw ArgumentError('El puesto del vendedor no puede estar vacío.');
    }

    final docRef = _db.collection('emergencies').doc();
    final savedEmergency = EmergencyModel(
      id: docRef.id,
      userId: emergency.userId,
      userName: emergency.userName,
      role: emergency.role,
      shopName: normalizedShopName,
      latitude: emergency.latitude,
      longitude: emergency.longitude,
      timestamp: emergency.timestamp,
      status: emergency.status,
      smsStatus: emergency.smsStatus,
      isTest: emergency.isTest,
      notifiedVendorIds: emergency.notifiedVendorIds,
    );

    try {
      final userRef = _db.collection('users').doc(emergency.userId);
      final result = await _db.runTransaction<EmergencyModel>((
        transaction,
      ) async {
        final userSnapshot = await transaction.get(userRef);
        if (!userSnapshot.exists) {
          throw StateError('El perfil autenticado ya no existe.');
        }

        final userData = userSnapshot.data()!;
        final expectedRole = userData['isVendor'] == true ? 'vendor' : 'client';
        if (emergency.role != expectedRole) {
          throw StateError(
            'El rol local no coincide con el perfil autenticado.',
          );
        }
        if (emergency.role == 'vendor') {
          final vendorRef = _db.collection('vendors').doc(emergency.userId);
          final vendorSnapshot = await transaction.get(vendorRef);
          if (!vendorSnapshot.exists ||
              vendorSnapshot.data()?['shopName'] != normalizedShopName) {
            throw StateError(
              'El puesto no coincide con el perfil autenticado.',
            );
          }
        }

        final activeEmergencyId = userData['activeEmergencyId'] as String?;
        if (activeEmergencyId != null && activeEmergencyId.isNotEmpty) {
          final activeRef = _db
              .collection('emergencies')
              .doc(activeEmergencyId);
          final activeSnapshot = await transaction.get(activeRef);
          final activeData = activeSnapshot.data();
          if (activeSnapshot.exists &&
              activeData?['userId'] == emergency.userId &&
              activeData?['status'] == 'active') {
            final data = activeData!..['id'] = activeSnapshot.id;
            final activeEmergency = EmergencyModel.fromJson(data);
            if (_isVisibleEmergency(activeEmergency)) return activeEmergency;

            transaction.update(activeRef, {
              'status': 'resolved',
              'resolvedAt': FieldValue.serverTimestamp(),
            });
          }
        }

        final emergencyData = savedEmergency.toJson()
          ..['timestamp'] = FieldValue.serverTimestamp()
          ..remove('smsStatus')
          ..remove('notifiedVendorIds')
          ..remove('surveyNotificationStatus');
        transaction.set(docRef, emergencyData);
        transaction.update(userRef, {'activeEmergencyId': docRef.id});
        return savedEmergency;
      });
      debugPrint('Emergencia activa: ${result.id}');
      if (result.id != docRef.id) return result;
      if (!savedEmergency.isTest) {
        await AppTelemetryService.logEmergencyCreated();
      }

      try {
        final committedSnapshot = await docRef
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 3));
        final committedData = committedSnapshot.data();
        if (committedData != null) {
          committedData['id'] = committedData['id'] ?? docRef.id;
          return EmergencyModel.fromJson(committedData);
        }
      } catch (error) {
        debugPrint('No se pudo leer el timestamp confirmado: $error');
      }
      return result;
    } catch (e) {
      debugPrint('Error al crear la emergencia en Firestore: $e');
      rethrow;
    }
  }

  /// 8. Guarda/actualiza el token FCM del vendedor — necesario para poder
  /// enviarle una notificación push cuando haya una emergencia cerca.
  Future<void> updateVendorFcmToken({
    required String vendorId,
    required String fcmToken,
  }) async {
    try {
      await _db.collection('vendors').doc(vendorId).set({
        'fcmToken': fcmToken,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error al guardar el token FCM del vendedor: $e');
    }
  }
}
