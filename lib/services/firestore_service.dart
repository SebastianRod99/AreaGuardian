import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/vendor_model.dart';
import '../models/emergency_model.dart';
import '../models/user_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const Duration emergencyVisibilityDuration = Duration(minutes: 20);

  Future<void> saveUserProfile(UserModel user) async {
    final authenticatedUser = FirebaseAuth.instance.currentUser;
    if (authenticatedUser == null || authenticatedUser.uid != user.id) {
      throw StateError('El perfil debe pertenecer al usuario autenticado.');
    }
    try {
      await _db
          .collection('users')
          .doc(user.id)
          .set(user.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error al guardar el perfil del usuario: $e');
      rethrow;
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
      await _db
          .collection('vendors')
          .doc(vendor.id)
          .set(vendor.toJson(), SetOptions(merge: true));
      await _db.collection('public_vendors').doc(vendor.id).set({
        'id': vendor.id,
        'shopName': vendor.shopName,
        'address': vendor.address,
        'latitude': vendor.latitude,
        'longitude': vendor.longitude,
        'isActive': vendor.isActive,
        'nequiNumber': vendor.nequiNumber,
        'daviplataNumber': vendor.daviplataNumber,
        'llaveNumber': vendor.llaveNumber,
        'catalog': vendor.catalog,
      }, SetOptions(merge: true));
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
    await _db.collection('public_vendors').doc(vendorId).set({
      'isActive': isActive,
    }, SetOptions(merge: true));
  }

  Future<VendorModel?> getVendor(String vendorId) async {
    final snapshot = await _db.collection('vendors').doc(vendorId).get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    final data = snapshot.data()!..['id'] = snapshot.id;
    return VendorModel.fromJson(data);
  }

  Future<void> updateVendorFixedLocation({
    required String vendorId,
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    final updates = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
    };
    if (address != null) updates['address'] = address;
    await _db.collection('vendors').doc(vendorId).update(updates);
    await _db
        .collection('public_vendors')
        .doc(vendorId)
        .set(updates, SetOptions(merge: true));
  }

  Future<void> updateVendorAddress({
    required String vendorId,
    required String address,
  }) async {
    await _db.collection('vendors').doc(vendorId).update({'address': address});
    await _db.collection('public_vendors').doc(vendorId).set({
      'address': address,
    }, SetOptions(merge: true));
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
    await _db.collection('public_vendors').doc(vendorId).set({
      'shopName': shopName,
      'address': address,
      'catalog': catalog,
    }, SetOptions(merge: true));
  }

  Future<List<EmergencyModel>> fetchActiveEmergencies() async {
    try {
      final snapshot = await _db
          .collection('emergencies')
          .where('status', isEqualTo: 'active')
          .get();
      return snapshot.docs
          .map((doc) {
            final data = doc.data();
            data['id'] = data['id'] ?? doc.id;
            return EmergencyModel.fromJson(data);
          })
          .where(_isVisibleEmergency)
          .toList();
    } catch (e) {
      debugPrint('Error al consultar emergencias activas: $e');
      return [];
    }
  }

  Stream<List<EmergencyModel>> watchActiveEmergencies() {
    return _db
        .collection('emergencies')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) {
                final data = doc.data();
                data['id'] = data['id'] ?? doc.id;
                return EmergencyModel.fromJson(data);
              })
              .where(_isVisibleEmergency)
              .toList(),
        );
  }

  bool _isVisibleEmergency(EmergencyModel emergency) {
    return DateTime.now().difference(emergency.timestamp) <
        emergencyVisibilityDuration;
  }

  Future<void> resolveEmergency(String emergencyId) async {
    await _db.collection('emergencies').doc(emergencyId).update({
      'status': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 6. Crea el registro de una emergencia y adjunta los ids de los puestos
  /// activos dentro del radio dado, listos para ser notificados (Sprint 2).
  Future<EmergencyModel> createEmergency({
    required String userId,
    required String userName,
    required double latitude,
    required double longitude,
    double radiusMeters = 1000,
  }) async {
    final authenticatedUser = FirebaseAuth.instance.currentUser;
    if (authenticatedUser == null || authenticatedUser.uid != userId) {
      throw StateError(
        'Debes iniciar sesión con Google para crear una alerta.',
      );
    }
    final List<String> nearbyVendorIds = await _findActiveVendorIdsNear(
      latitude,
      longitude,
      radiusMeters,
    );

    final docRef = _db.collection('emergencies').doc();

    final emergency = EmergencyModel(
      id: docRef.id,
      userId: userId,
      userName: userName,
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      status: 'active',
      notifiedVendorIds: nearbyVendorIds,
    );

    try {
      await docRef.set(emergency.toJson());
      debugPrint(
        'Emergencia creada: ${docRef.id} — ${nearbyVendorIds.length} puestos activos en el radio',
      );
    } catch (e) {
      debugPrint('Error al crear la emergencia en Firestore: $e');
      rethrow;
    }

    return emergency;
  }

  /// Filtra puestos activos usando exclusivamente su ubicación comercial fija.
  Future<List<String>> _findActiveVendorIdsNear(
    double lat,
    double lng,
    double radiusMeters,
  ) async {
    try {
      final snapshot = await _db
          .collection('vendors')
          .where('isActive', isEqualTo: true)
          .get();

      return snapshot.docs
          .where((doc) {
            final data = doc.data();
            final double vLat = (data['latitude'] as num?)?.toDouble() ?? 0.0;
            final double vLng = (data['longitude'] as num?)?.toDouble() ?? 0.0;

            final double distance = Geolocator.distanceBetween(
              lat,
              lng,
              vLat,
              vLng,
            );
            return distance <= radiusMeters;
          })
          .map((doc) => doc.id)
          .toList();
    } catch (e) {
      debugPrint('Error al buscar puestos activos cercanos: $e');
      return [];
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
