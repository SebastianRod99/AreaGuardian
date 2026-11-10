import 'package:areaguardian/models/emergency_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializa la emergencia sin estado de SMS remoto', () {
    final emergency = EmergencyModel(
      id: 'emergency-1',
      userId: 'user-1',
      userName: 'Vendedor',
      role: 'vendor',
      shopName: 'Puesto',
      latitude: 4.65,
      longitude: -74.1,
      timestamp: DateTime.utc(2026, 10, 15),
    );

    expect(emergency.toJson().containsKey('smsStatus'), isFalse);
    expect(EmergencyModel.fromJson(emergency.toJson()).id, emergency.id);
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
    expect(EmergencyModel.fromJson(emergency.toJson()).isTest, isTrue);
    expect(
      EmergencyModel.fromJson({...emergency.toJson()}..remove('isTest')).isTest,
      isFalse,
    );
  });
}
