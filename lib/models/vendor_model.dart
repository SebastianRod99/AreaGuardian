class VendorModel {
  final String id;
  final String userId;
  final String shopName;
  final String vendorName; // <-- Añadido por si tu formulario lo usa
  final String category;

  // Ubicación Fija / Comercial del Puesto
  final double latitude;
  final double longitude;

  // Ubicación en Tiempo Real / Dinámica
  final double currentLatitude;
  final double currentLongitude;

  final String nequiNumber;
  final String daviplataNumber;
  final bool isActive;
  final DateTime? lastSeen;

  VendorModel({
    required this.id,
    required this.userId,
    required this.shopName,
    required this.vendorName,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.currentLatitude,
    required this.currentLongitude,
    required this.nequiNumber,
    required this.daviplataNumber,
    this.isActive = true,
    this.lastSeen,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'shopName': shopName,
      'vendorName': vendorName,
      'category': category,
      'latitude': latitude,
      'longitude': longitude,
      'currentLatitude': currentLatitude,
      'currentLongitude': currentLongitude,
      'nequiNumber': nequiNumber,
      'daviplataNumber': daviplataNumber,
      'isActive': isActive,
      'lastSeen': lastSeen?.toIso8601String(),
    };
  }

  factory VendorModel.fromJson(Map<String, dynamic> json) {
    return VendorModel(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      shopName: json['shopName'] ?? '',
      vendorName: json['vendorName'] ?? '',
      category: json['category'] ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      currentLatitude: (json['currentLatitude'] as num?)?.toDouble() ?? (json['latitude'] as num?)?.toDouble() ?? 0.0,
      currentLongitude: (json['currentLongitude'] as num?)?.toDouble() ?? (json['longitude'] as num?)?.toDouble() ?? 0.0,
      nequiNumber: json['nequiNumber'] ?? '',
      daviplataNumber: json['daviplataNumber'] ?? '',
      isActive: json['isActive'] ?? true,
      lastSeen: json['lastSeen'] != null ? DateTime.tryParse(json['lastSeen']) : null,
    );
  }
  VendorModel copyWith({
    String? shopName,
    String? vendorName,
    double? latitude,
    double? longitude,
    double? currentLatitude,
    double? currentLongitude,
    bool? isActive,
    DateTime? lastSeen,
  }) {
    return VendorModel(
      id: id,
      userId: userId,
      shopName: shopName ?? this.shopName,
      vendorName: vendorName ?? this.vendorName,
      category: category,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      currentLatitude: currentLatitude ?? this.currentLatitude,
      currentLongitude: currentLongitude ?? this.currentLongitude,
      nequiNumber: nequiNumber,
      daviplataNumber: daviplataNumber,
      isActive: isActive ?? this.isActive,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}