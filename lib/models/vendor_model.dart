import 'package:cloud_firestore/cloud_firestore.dart';

class VendorModel {
  final String id;
  final String userId;
  final String shopName;
  final String address;
  final String vendorName; // <-- Añadido por si tu formulario lo usa
  final String category;

  // Ubicación Fija / Comercial del Puesto
  final double latitude;
  final double longitude;
  final double? currentLatitude;
  final double? currentLongitude;
  final DateTime? lastLocationUpdate;

  final String nequiNumber;
  final String daviplataNumber;
  final String llaveNumber;
  final List<String> catalog;
  final bool isActive;
  final DateTime? lastSeen;
  // Token de notificaciones push (Sprint 2). Nulo hasta que el dispositivo
  // se registra en NotificationService — no todos los documentos lo tienen.
  final String? fcmToken;

  VendorModel({
    required this.id,
    required this.userId,
    required this.shopName,
    this.address = '',
    required this.vendorName,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.currentLatitude,
    this.currentLongitude,
    this.lastLocationUpdate,
    required this.nequiNumber,
    required this.daviplataNumber,
    this.llaveNumber = '',
    this.catalog = const [],
    this.isActive = true,
    this.lastSeen,
    this.fcmToken,
  });

  double get fixedLatitude => latitude;
  double get fixedLongitude => longitude;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'shopName': shopName,
      'address': address,
      'vendorName': vendorName,
      'category': category,
      'latitude': latitude,
      'longitude': longitude,
      if (currentLatitude != null) 'currentLatitude': currentLatitude,
      if (currentLongitude != null) 'currentLongitude': currentLongitude,
      if (lastLocationUpdate != null)
        'lastLocationUpdate': lastLocationUpdate!.toIso8601String(),
      'nequiNumber': nequiNumber,
      'daviplataNumber': daviplataNumber,
      'llaveNumber': llaveNumber,
      'catalog': catalog,
      'isActive': isActive,
      'lastSeen': lastSeen?.toIso8601String(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    };
  }

  factory VendorModel.fromJson(Map<String, dynamic> json) {
    return VendorModel(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      shopName: json['shopName'] ?? '',
      address: json['address'] ?? '',
      vendorName: json['vendorName'] ?? '',
      category: json['category'] ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      currentLatitude: (json['currentLatitude'] as num?)?.toDouble(),
      currentLongitude: (json['currentLongitude'] as num?)?.toDouble(),
      lastLocationUpdate: _parseLastSeen(json['lastLocationUpdate']),
      nequiNumber: json['nequiNumber'] ?? '',
      daviplataNumber: json['daviplataNumber'] ?? '',
      llaveNumber: json['llaveNumber'] ?? '',
      catalog:
          (json['catalog'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      isActive: json['isActive'] ?? true,
      lastSeen: _parseLastSeen(json['lastSeen']),
      fcmToken: json['fcmToken'] as String?,
    );
  }

  /// 'lastSeen' puede venir como String ISO8601 o como Timestamp de Firestore.
  static DateTime? _parseLastSeen(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  VendorModel copyWith({
    String? shopName,
    String? address,
    String? vendorName,
    double? latitude,
    double? longitude,
    double? currentLatitude,
    double? currentLongitude,
    DateTime? lastLocationUpdate,
    bool? isActive,
    DateTime? lastSeen,
    String? fcmToken,
    String? nequiNumber,
    String? daviplataNumber,
    String? llaveNumber,
    List<String>? catalog,
  }) {
    return VendorModel(
      id: id,
      userId: userId,
      shopName: shopName ?? this.shopName,
      address: address ?? this.address,
      vendorName: vendorName ?? this.vendorName,
      category: category,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      currentLatitude: currentLatitude ?? this.currentLatitude,
      currentLongitude: currentLongitude ?? this.currentLongitude,
      lastLocationUpdate: lastLocationUpdate ?? this.lastLocationUpdate,
      nequiNumber: nequiNumber ?? this.nequiNumber,
      daviplataNumber: daviplataNumber ?? this.daviplataNumber,
      llaveNumber: llaveNumber ?? this.llaveNumber,
      catalog: catalog ?? this.catalog,
      isActive: isActive ?? this.isActive,
      lastSeen: lastSeen ?? this.lastSeen,
      fcmToken: fcmToken ?? this.fcmToken,
    );
  }
}
