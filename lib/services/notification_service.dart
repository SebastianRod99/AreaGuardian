import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:areaguardian/screens/map_dashboard_screen.dart';
import 'firestore_service.dart';

/// Se usa para navegar (ej. al mapa) desde fuera del árbol de widgets,
/// cuando el usuario toca una notificación de emergencia. Debe pasarse
/// como `navigatorKey` al MaterialApp en main.dart.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const String emergencyChannelId = 'emergency_alerts_channel';
const String emergencyChannelName = 'Alertas de emergencia';
const String emergencyChannelDescription =
    'Notificaciones de emergencias cercanas — suenan con alta prioridad';

/// Handler de mensajes FCM en segundo plano. DEBE ser una función de nivel
/// superior (no un método de clase) y llevar @pragma('vm:entry-point') para
/// que el motor de Flutter pueda invocarla en su propio isolate cuando la
/// app está en background o completamente cerrada.
///
/// Cuando el mensaje enviado desde la Cloud Function incluye un bloque
/// "notification", Android ya la muestra automáticamente usando el canal
/// por defecto declarado en AndroidManifest.xml — no hace falta construirla
/// aquí a mano. Este handler queda como punto de extensión (ej. logging).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📩 Notificación de emergencia recibida en background: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirestoreService _firestoreService = FirestoreService();

  bool _initialized = false;

  /// Debe llamarse una sola vez por sesión (lo hace AppShell en bar_nav.dart
  /// apenas hay un usuario logueado). Es seguro llamarla varias veces: la
  /// segunda vez no hace nada.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _createNotificationChannel();
    await _initLocalNotifications();
    await _requestPermissions();
    await _registerFcmToken();

    // El token puede cambiar (reinstalación, borrado de datos del sistema, etc.)
    _messaging.onTokenRefresh.listen((_) => _registerFcmToken());

    // App en PRIMER PLANO: FCM no muestra un banner automático, así que lo
    // mostramos nosotros mismos con el mismo canal/sonido que usa el fondo.
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // El usuario tocó la notificación con la app en BACKGROUND (no cerrada).
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // La app estaba COMPLETAMENTE CERRADA y se abrió tocando la notificación.
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  Future<void> _createNotificationChannel() async {
    const androidChannel = AndroidNotificationChannel(
      emergencyChannelId,
      emergencyChannelName,
      description: emergencyChannelDescription,
      importance: Importance.max,
      playSound: true,
      // Requiere que exista android/app/src/main/res/raw/alarm.mp3
      // (copiar desde assets/audio/alarm.mp3 — ver instrucciones abajo).
      sound: RawResourceAndroidNotificationSound('alarm'),
      enableVibration: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        _navigateToEmergency(jsonDecode(payload) as Map<String, dynamic>);
      },
    );
  }

  Future<void> _requestPermissions() async {
    // Cubre iOS y el permiso POST_NOTIFICATIONS de Android 13+ en una sola llamada.
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  Future<void> _registerFcmToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;

      final vendorId = await _getVendorIdIfAny();
      if (vendorId == null) return; // solo los vendedores reciben alertas

      await _firestoreService.updateVendorFcmToken(
        vendorId: vendorId,
        fcmToken: token,
      );
    } catch (e) {
      debugPrint('Error registrando el token FCM: $e');
    }
  }

  Future<String?> _getVendorIdIfAny() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('vendor_id');
    return (id == null || id.isEmpty) ? null : id;
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          emergencyChannelId,
          emergencyChannelName,
          channelDescription: emergencyChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('alarm'),
          enableVibration: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    _navigateToEmergency(message.data);
  }

  void _navigateToEmergency(Map<String, dynamic> data) {
    final double? lat = double.tryParse('${data['latitude']}');
    final double? lng = double.tryParse('${data['longitude']}');
    if (lat == null || lng == null) return;

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => MapDashboardScreen(
          focusLatitude: lat,
          focusLongitude: lng,
        ),
      ),
    );
  }
}