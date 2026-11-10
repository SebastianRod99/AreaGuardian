import 'package:cloud_firestore/cloud_firestore.dart';

class EmergencyModel {
  final String id;
  final String userId;
  final String userName;
  final String role;
  final String shopName;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String status; // 'active', 'resolved'
  final bool isTest;
  final List<String> notifiedVendorIds;

  EmergencyModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.role,
    required this.shopName,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.status = 'active',
    this.isTest = false,
    this.notifiedVendorIds = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'role': role,
      'shopName': shopName,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'status': status,
      'isTest': isTest,
      'notifiedVendorIds': notifiedVendorIds,
    };
  }

  factory EmergencyModel.fromJson(Map<String, dynamic> json) {
    return EmergencyModel(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      role: json['role'] ?? 'client',
      shopName: json['shopName'] ?? 'Vecino',
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      timestamp: _parseTimestamp(json['timestamp']),
      status: json['status'] ?? 'active',
      isTest: json['isTest'] == true,
      notifiedVendorIds:
          (json['notifiedVendorIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
