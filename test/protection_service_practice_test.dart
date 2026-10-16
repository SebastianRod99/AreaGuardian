import 'package:areaguardian/services/protection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProtectionService en modo práctica', () {
    test('completa cuatro sacudidas bruscas sin activar emergencias', () {
      var emergencyCount = 0;
      final service = ProtectionService(
        practiceMode: true,
        onEmergencyTriggered: () => emergencyCount++,
      )..activate(listen: false);
      final start = DateTime(2026, 10, 15);

      for (var index = 0; index < 4; index++) {
        final shakeAt = start.add(Duration(milliseconds: index * 1100));
        service.handleShakeEvent(shakeAt, 16);
        service.handleShakeEvent(
          shakeAt.add(const Duration(milliseconds: 20)),
          0,
        );
        service.handleShakeEvent(
          shakeAt.add(const Duration(milliseconds: 300)),
          0,
        );
      }

      expect(service.shakeCount, 4);
      expect(service.isPracticeComplete, isTrue);
      expect(emergencyCount, 0);
      service.deactivate();
      service.dispose();
    });

    test('descarta una secuencia rítmica de marcha y explica el motivo', () {
      var emergencyCount = 0;
      final service = ProtectionService(
        practiceMode: true,
        onEmergencyTriggered: () => emergencyCount++,
      )..activate(listen: false);
      final start = DateTime(2026, 10, 15);

      for (var index = 0; index < 4; index++) {
        final shakeAt = start.add(Duration(milliseconds: index * 500));
        service.handleShakeEvent(shakeAt, 16);
        service.handleShakeEvent(
          shakeAt.add(const Duration(milliseconds: 20)),
          0,
        );
        service.handleShakeEvent(
          shakeAt.add(const Duration(milliseconds: 300)),
          0,
        );
      }

      expect(service.shakeCount, 0);
      expect(service.isPracticeComplete, isFalse);
      expect(service.shakeRejectionReason, contains('Parece que caminas'));
      expect(emergencyCount, 0);
      service.deactivate();
      service.dispose();
    });

    test('ignora movimiento sostenido e inclinación como disparadores', () {
      var emergencyCount = 0;
      final service = ProtectionService(
        practiceMode: true,
        onEmergencyTriggered: () => emergencyCount++,
      )..activate(listen: false);
      final start = DateTime(2026, 10, 15);

      service.handleMotionSample(
        start,
        userAcceleration: 3,
        gyroscopeMagnitude: 1.5,
        tiltDegrees: 30,
      );
      service.handleMotionSample(
        start.add(const Duration(seconds: 11)),
        userAcceleration: 3,
        gyroscopeMagnitude: 1.5,
        tiltDegrees: 30,
      );

      expect(service.isPracticeComplete, isFalse);
      expect(emergencyCount, 0);
      service.deactivate();
      service.dispose();
    });
  });
}
