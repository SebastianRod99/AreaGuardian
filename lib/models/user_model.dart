class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final bool isVendor;
  final double? latitude;
  final double? longitude;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.isVendor = false,
    this.latitude,
    this.longitude,
  });

  // Convertir a JSON para futuras bases de datos
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'isVendor': isVendor,
      'latitude': latitude,
      'longitude': longitude,
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
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
    );
  }
}