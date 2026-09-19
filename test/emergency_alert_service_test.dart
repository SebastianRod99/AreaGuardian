import 'package:flutter_test/flutter_test.dart';
import 'package:areaguardian/services/emergency_alert_service.dart';

void main() {
  test('resetea por timeout de 5 segundos y permite una nueva secuencia', () {
    var triggered = 0;
    final service = ProtectionService(
      onEmergencyTriggered: () => triggered++,
      onConfirmationVibration: () async {},
    );

    final start = DateTime(2024, 1, 1, 12, 0, 0);

    service.handleShakeEvent(start, 20.0);
    service.handleShakeEvent(start.add(const Duration(seconds: 2)), 20.0);
    service.handleShakeEvent(start.add(const Duration(seconds: 4)), 20.0);
    service.handleShakeEvent(
      start.add(const Duration(seconds: 4, milliseconds: 100)),
      20.0,
    );

    expect(triggered, 1);
    expect(service.shakeCount, 0);

    service.handleShakeEvent(start.add(const Duration(seconds: 10)), 20.0);
    service.handleShakeEvent(start.add(const Duration(seconds: 11)), 20.0);
    service.handleShakeEvent(start.add(const Duration(seconds: 12)), 20.0);
    service.handleShakeEvent(start.add(const Duration(seconds: 13)), 20.0);

    expect(triggered, 2);
    expect(service.shakeCount, 0);
  });
}
