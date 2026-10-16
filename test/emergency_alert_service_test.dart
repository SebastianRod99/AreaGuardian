import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:areaguardian/services/emergency_alert_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'una sacudida sostenida cuenta una sola vez hasta el rearme estable',
    () {
      var triggered = 0;
      final service = ProtectionService(
        onEmergencyTriggered: () async {
          triggered++;
        },
      );
      service.activate(listen: false);

      final start = DateTime(2024, 1, 1, 12, 0, 0);

      service.handleShakeEvent(start, 20.0);
      service.handleShakeEvent(
        start.add(const Duration(milliseconds: 200)),
        20.0,
      );
      expect(service.shakeCount, 1);

      service.handleShakeEvent(
        start.add(const Duration(milliseconds: 250)),
        9.8,
      );
      service.handleShakeEvent(
        start.add(const Duration(milliseconds: 500)),
        9.8,
      );
      service.handleShakeEvent(
        start.add(const Duration(milliseconds: 600)),
        20.0,
      );

      expect(service.shakeCount, 2);
      expect(triggered, 0);

      service.deactivate();
    },
  );

  test('reinicia la secuencia al vencer la ventana de cinco segundos', () {
    final service = ProtectionService();
    service.activate(listen: false);

    final start = DateTime(2024, 1, 1, 12, 0, 0);
    void addShake(DateTime at) {
      service.handleShakeEvent(at, 20.0);
      service.handleShakeEvent(at.add(const Duration(milliseconds: 150)), 9.8);
      service.handleShakeEvent(at.add(const Duration(milliseconds: 400)), 9.8);
    }

    addShake(start);
    addShake(start.add(const Duration(seconds: 1)));
    expect(service.shakeCount, 2);

    addShake(start.add(const Duration(seconds: 6)));
    expect(service.shakeCount, 1);

    service.deactivate();
  });

  test(
    'activa solo al cuarto movimiento y mantiene el contador en cuatro',
    () async {
      final triggers = <bool>[];
      final callbackCompleted = Completer<void>();
      final service = ProtectionService(
        onEmergencyTriggered: () {
          triggers.add(true);
          callbackCompleted.complete();
        },
      );
      service.activate(listen: false);

      final start = DateTime(2024, 1, 1, 12, 0, 0);
      for (var index = 0; index < 4; index++) {
        final shakeAt = start.add(Duration(seconds: index));
        service.handleShakeEvent(shakeAt, 20.0);
        service.handleShakeEvent(
          shakeAt.add(const Duration(milliseconds: 150)),
          9.8,
        );
        service.handleShakeEvent(
          shakeAt.add(const Duration(milliseconds: 400)),
          9.8,
        );
      }

      await callbackCompleted.future;
      expect(triggers, hasLength(1));
      expect(service.shakeCount, 4);

      service.handleShakeEvent(start.add(const Duration(seconds: 5)), 20.0);
      expect(triggers, hasLength(1));
      expect(service.shakeCount, 4);

      service.deactivate();
      expect(service.shakeCount, 0);
      service.activate(listen: false);
      expect(service.shakeCount, 0);
      service.handleShakeEvent(start.add(const Duration(seconds: 6)), 20.0);
      expect(service.shakeCount, 1);

      service.deactivate();
    },
  );

  test('ignora agitadas cuando la guardia no está activa', () {
    var triggered = 0;
    final service = ProtectionService(onEmergencyTriggered: () => triggered++);
    final start = DateTime(2024, 1, 1, 12, 0, 0);

    for (var index = 0; index < 4; index++) {
      service.handleShakeEvent(start.add(Duration(seconds: index)), 20.0);
    }

    expect(triggered, 0);
    expect(service.shakeCount, 0);
  });

  test(
    'bloquea una activación concurrente y permite reintentar tras fallo',
    () {
      final service = ProtectionService();
      service.activate(listen: false);

      expect(service.beginEmergencyActivation(), isTrue);
      expect(service.isEmergencyInProgress, isTrue);
      expect(service.beginEmergencyActivation(), isFalse);

      service.failEmergencyActivation();
      expect(service.isEmergencyInProgress, isFalse);
      expect(service.isAlarmActive, isFalse);
      expect(service.isProtected, isTrue);
      expect(service.shakeCount, 0);
      expect(service.beginEmergencyActivation(), isTrue);

      service.failEmergencyActivation();
      service.deactivate();
    },
  );

  test('una emergencia activa bloquea nuevas activaciones hasta resolver', () {
    final service = ProtectionService();
    service.activate(listen: false);
    expect(service.beginEmergencyActivation(), isTrue);

    service.markAlarmActive('emergency-1');
    expect(service.isEmergencyInProgress, isFalse);
    expect(service.isAlarmActive, isTrue);
    expect(service.activeEmergencyId, 'emergency-1');
    expect(service.beginEmergencyActivation(), isFalse);

    service.clearActiveEmergencyId();
    service.clearAlarm();
    expect(service.isAlarmActive, isFalse);
    expect(service.beginEmergencyActivation(), isTrue);

    service.failEmergencyActivation();
    service.deactivate();
  });

  test('filtra cuatro impactos rítmicos de trote', () {
    var triggered = 0;
    final service = ProtectionService(onEmergencyTriggered: () => triggered++);
    service.activate(listen: false);

    final start = DateTime(2024, 1, 1, 12, 0, 0);
    for (var index = 0; index < 4; index++) {
      final impactAt = start.add(Duration(milliseconds: index * 500));
      service.handleShakeEvent(impactAt, 20.0);
      service.handleShakeEvent(
        impactAt.add(const Duration(milliseconds: 150)),
        9.8,
      );
      service.handleShakeEvent(
        impactAt.add(const Duration(milliseconds: 400)),
        9.8,
      );
    }

    expect(triggered, 0);
    expect(service.shakeCount, 0);
    service.deactivate();
  });

  test(
    'dispara tras diez segundos de movimiento irregular sostenido',
    () async {
      final callbackCompleted = Completer<void>();
      var triggered = 0;
      final service = ProtectionService(
        onEmergencyTriggered: () {
          triggered++;
          callbackCompleted.complete();
        },
      );
      service.activate(listen: false);

      final start = DateTime(2024, 1, 1, 12, 0, 0);
      final pulseOffsets = [
        0,
        320,
        900,
        1260,
        1950,
        2260,
        2730,
        3450,
        3790,
        4410,
        4800,
        5510,
        5800,
        6340,
        6710,
        7390,
        7720,
        8310,
        8710,
        9440,
        9740,
        10260,
      ];
      for (final milliseconds in pulseOffsets) {
        final pulseAt = start.add(Duration(milliseconds: milliseconds));
        service.handleMotionSample(pulseAt, userAcceleration: 3.5);
        service.handleMotionSample(
          pulseAt.add(const Duration(milliseconds: 100)),
          userAcceleration: 0,
        );
      }

      await callbackCompleted.future;
      expect(triggered, 1);
      service.deactivate();
    },
  );

  test(
    'dispara tras diez segundos de inclinación estable superior a 20°',
    () async {
      final callbackCompleted = Completer<void>();
      var triggered = 0;
      final service = ProtectionService(
        onEmergencyTriggered: () {
          triggered++;
          callbackCompleted.complete();
        },
      );
      service.activate(listen: false);

      final start = DateTime(2024, 1, 1, 12, 0, 0);
      for (var second = 0; second <= 10; second++) {
        service.handleMotionSample(
          start.add(Duration(seconds: second)),
          userAcceleration: 0,
          tiltDegrees: 25,
        );
      }

      await callbackCompleted.future;
      expect(triggered, 1);
      service.deactivate();
    },
  );

  test('no dispara el modo sostenido por movimiento rítmico de trote', () {
    var triggered = 0;
    final service = ProtectionService(onEmergencyTriggered: () => triggered++);
    service.activate(listen: false);

    final start = DateTime(2024, 1, 1, 12, 0, 0);
    const gaitCycle = [3.0, 3.4, 4.0, 3.4, 3.0];
    for (var sample = 0; sample <= 100; sample++) {
      service.handleMotionSample(
        start.add(Duration(milliseconds: sample * 100)),
        userAcceleration: gaitCycle[sample % gaitCycle.length],
      );
    }

    expect(triggered, 0);
    expect(service.isAlarmActive, isFalse);
    service.deactivate();
  });
}
