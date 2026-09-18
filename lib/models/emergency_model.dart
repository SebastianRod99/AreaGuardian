class EmergencyModel {
  final String id;
  final String userId;
  final String userName;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String status; // 'active', 'resolved'
  // Puestos activos que quedaron dentro del radio al momento de crear la
  // emergencia (calculado en FirestoreService.createEmergency). Es lo que
  // lee la Cloud Function para saber a quién notificar.
  final List<String> notifiedVendorIds;

  EmergencyModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.status = 'active',
    this.notifiedVendorIds = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'status': status,
      'notifiedVendorIds': notifiedVendorIds,
    };
  }

  factory EmergencyModel.fromJson(Map<String, dynamic> json) {
    return EmergencyModel(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      status: json['status'] ?? 'active',
      notifiedVendorIds: (json['notifiedVendorIds'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
          const [],
    );
  }
}