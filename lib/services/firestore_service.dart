import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/vendor_model.dart';
import '../models/emergency_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 1. Guarda o actualiza el perfil completo del vendedor (Puesto Fijo + Estado Inicial)
  Future<void> saveVendorProfile(VendorModel vendor) async {
    try {
      await _db.collection('vendors').doc(vendor.id).set(vendor.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error al guardar el perfil del vendedor: $e');
      rethrow;
    }
  }

  /// 2. Obtiene la lista de todos los puestos de la red
  Future<List<VendorModel>> fetchNearbyVendors() async {
    try {
      QuerySnapshot snapshot = await _db.collection('vendors').get();

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

  /// 3. Actualiza únicamente la ubicación en tiempo real del usuario (mientras camina/patrulla)
  Future<void> updateCurrentLocation(String vendorId, double lat, double lng) async {
    try {
      await _db.collection('vendors').doc(vendorId).update({
        'currentLatitude': lat,
        'currentLongitude': lng,
        'lastSeen': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error al actualizar ubicación en tiempo real: $e');
    }
  }

  /// 4. Control de Actividad ("latido" o confirmación de que sigue abierto/activo)
  Future<void> updateVendorLiveLocation({
    required String vendorId,
    required double currentLatitude,
    required double currentLongitude,
    required bool isActive,
  }) async {
    try{
      await _db.collection('vendors').doc(vendorId).update({
        'currentLatitude': currentLatitude,
        'currentLongitude': currentLongitude,
        'isActive': isActive,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error al actualizar ubicación en vivo: $e');
    }
  }

  /// 5. Actualiza la ubicación en tiempo real de un CLIENTE (o dueño usando la
  /// guardia). Se guarda en una colección aparte de 'vendors' porque un
  /// cliente no tiene puesto fijo ni categoría — solo identidad + posición.
  Future<void> updateClientLiveLocation({
    required String clientId,
    required String clientName,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _db.collection('clients').doc(clientId).set({
        'id': clientId,
        'name': clientName,
        'latitude': latitude,
        'longitude': longitude,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error al actualizar ubicación en vivo del cliente: $e');
    }
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
      debugPrint('Emergencia creada: ${docRef.id} — ${nearbyVendorIds.length} puestos activos en el radio');
    } catch (e) {
      debugPrint('Error al crear la emergencia en Firestore: $e');
      rethrow;
    }

    return emergency;
  }

  /// 7. Filtra, entre los puestos activos, los que están dentro del radio
  /// (en metros) usando la ubicación EN VIVO del dueño (con respaldo a la
  /// ubicación fija del puesto si aún no hay una lectura en vivo).
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

      return snapshot.docs.where((doc) {
        final data = doc.data();
        final double vLat = (data['currentLatitude'] as num?)?.toDouble() ??
            (data['latitude'] as num?)?.toDouble() ??
            0.0;
        final double vLng = (data['currentLongitude'] as num?)?.toDouble() ??
            (data['longitude'] as num?)?.toDouble() ??
            0.0;

        final double distance = Geolocator.distanceBetween(lat, lng, vLat, vLng);
        return distance <= radiusMeters;
      }).map((doc) => doc.id).toList();
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