import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class VendorForegroundService {
  static bool _initialized = false;
  static bool _vendorActive = false;
  static bool _guardActive = false;
  static Future<void>? _startInProgress;

  static void initialize() {
    if (_initialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'areaguardian_vendor_availability',
        channelName: 'Puesto activo',
        channelDescription:
            'Mantiene disponible el puesto y actualiza su ubicación.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
    _initialized = true;
  }

  static Future<void> start() async {
    _vendorActive = true;
    await _syncService();
  }

  static Future<void> startGuard() async {
    _guardActive = true;
    await _syncService();
  }

  static Future<void> _syncService() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final pendingStart = _startInProgress;
    if (pendingStart != null) return pendingStart;

    final startOperation = _startService();
    _startInProgress = startOperation;
    try {
      await startOperation;
    } finally {
      _startInProgress = null;
    }
  }

  static Future<void> _startService() async {
    initialize();
    final notificationText = _guardActive
        ? 'Guardia activa: detección de movimientos.'
        : 'Tu puesto está disponible para la comunidad.';
    if (await FlutterForegroundTask.isRunningService) {
      final updateResult = await FlutterForegroundTask.updateService(
        notificationTitle: _guardActive
            ? 'AreaGuardian: Guardia activa'
            : 'AreaGuardian: puesto activo',
        notificationText: notificationText,
      );
      if (updateResult is ServiceRequestFailure) {
        throw StateError(
          'No se pudo actualizar la notificación: ${updateResult.error}',
        );
      }
      return;
    }

    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      throw StateError('Activa las notificaciones para mantener la guardia.');
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 7301,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: _guardActive
          ? 'AreaGuardian: Guardia activa'
          : 'AreaGuardian: puesto activo',
      notificationText: notificationText,
      callback: startVendorTask,
    );

    if (result is ServiceRequestFailure) {
      throw StateError('No se pudo iniciar el servicio: ${result.error}');
    }
  }

  static Future<void> stop() async {
    _vendorActive = false;
    _guardActive = false;
    await _stopIfUnused();
  }

  static Future<void> stopVendor() async {
    _vendorActive = false;
    await _stopIfUnused();
  }

  static Future<void> stopGuard() async {
    _guardActive = false;
    await _stopIfUnused();
  }

  static Future<void> _stopIfUnused() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_vendorActive || _guardActive) {
      await _syncService();
      return;
    }
    final pendingStart = _startInProgress;
    if (pendingStart != null) await pendingStart;
    if (await FlutterForegroundTask.isRunningService) {
      final result = await FlutterForegroundTask.stopService();
      if (result is ServiceRequestFailure) {
        throw StateError('No se pudo detener el servicio: ${result.error}');
      }
    }
  }
}

@pragma('vm:entry-point')
void startVendorTask() {
  FlutterForegroundTask.setTaskHandler(_VendorTaskHandler());
}

class _VendorTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
