class VendorModel {
  final String id;
  final String userId;
  final String shopName;
  final String category;
  final double latitude;
  final double longitude;
  final String nequiNumber;
  final String daviplataNumber;
  final bool isActive;

  VendorModel({
    required this.id,
    required this.userId,
    required this.shopName,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.nequiNumber,
    required this.daviplataNumber,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'shopName': shopName,
      'category': category,
      'latitude': latitude,
      'longitude': longitude,
      'nequiNumber': nequiNumber,
      'daviplataNumber': daviplataNumber,
      'isActive': isActive,
    };
  }

  factory VendorModel.fromJson(Map<String, dynamic> json) {
    return VendorModel(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      shopName: json['shopName'] ?? '',
      category: json['category'] ?? '',
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      nequiNumber: json['nequiNumber'] ?? '',
      daviplataNumber: json['daviplataNumber'] ?? '',
      isActive: json['isActive'] ?? true,
    );
  }
}