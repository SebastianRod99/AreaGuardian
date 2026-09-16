import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/vendor_model.dart';

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
}