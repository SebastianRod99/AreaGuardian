class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final bool isVendor;
  final String? vendorId;
  final double? latitude;
  final double? longitude;
  final DateTime?
  lastSeen; // Opcional: útil para saber actividad reciente del usuario

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.isVendor = false,
    this.vendorId,
    this.latitude,
    this.longitude,
    this.lastSeen,
  });

  // Convertir a JSON para bases de datos (Firestore)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'isVendor': isVendor,
      if (vendorId != null) 'vendorId': vendorId,
      'latitude': latitude,
      'longitude': longitude,
      'lastSeen': lastSeen?.toIso8601String(),
    };
  }

  // Crear desde JSON (ej: Firebase o API)
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      isVendor: json['isVendor'] ?? false,
      vendorId: json['vendorId'] as String?,
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'])
          : null,
    );
  }

  // Método copyWith para actualizar coordenadas o datos del usuario fácilmente
  UserModel copyWith({
    String? name,
    String? email,
    String? phone,
    bool? isVendor,
    String? vendorId,
    double? latitude,
    double? longitude,
    DateTime? lastSeen,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      isVendor: isVendor ?? this.isVendor,
      vendorId: vendorId ?? this.vendorId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
