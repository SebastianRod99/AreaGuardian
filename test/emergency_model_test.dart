import 'package:areaguardian/models/emergency_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializa y restaura el estado del SMS', () {
    final emergency = EmergencyModel(
      id: 'emergency-1',
      userId: 'user-1',
      userName: 'Vendedor',
      role: 'vendor',
      shopName: 'Puesto',
      latitude: 4.65,
      longitude: -74.1,
      timestamp: DateTime.utc(2026, 10, 15),
      smsStatus: 'sent',
    );

    final legacyJson = emergency.toJson()..remove('smsStatus');
    expect(emergency.toJson()['smsStatus'], 'sent');
    expect(EmergencyModel.fromJson(emergency.toJson()).smsStatus, 'sent');
    expect(EmergencyModel.fromJson(legacyJson).smsStatus, 'pending');
  });

  test('marca los simulacros y conserva el campo en la serialización', () {
    final emergency = EmergencyModel(
      id: 'test-emergency',
      userId: 'user-1',
      userName: 'Vendedor',
      role: 'vendor',
      shopName: 'Puesto',
      latitude: 4.65,
      longitude: -74.1,
      timestamp: DateTime.utc(2026, 10, 15),
      isTest: true,
    );

    expect(emergency.toJson()['isTest'], isTrue);
    expect(
      EmergencyModel.fromJson(emergency.toJson()).isTest,
      isTrue,
    );
    expect(
      EmergencyModel.fromJson({...emergency.toJson()}..remove('isTest')).isTest,
      isFalse,
    );
  });
}
