import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:areaguardian/screens/map_dashboard_screen.dart';
import 'firestore_service.dart';

/// Se usa para navegar (ej. al mapa) desde fuera del árbol de widgets.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const String emergencyChannelId = 'emergency_alerts_channel';
const String emergencyChannelName = 'Alertas de emergencia';
const String emergencyChannelDescription =
    'Notificaciones de emergencias cercanas — suenan con alta prioridad';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📩 Notificación de emergencia recibida en background: ${message.messageId}');
}

/// Callback requerido para toques en segundo plano (DEBE ser top-level o static).
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  // Manejo opcional de toque en segundo plano
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

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _createNotificationChannel();
    await _initLocalNotifications();
    await _requestPermissions();
    await _registerFcmToken();

    _messaging.onTokenRefresh.listen((_) => _registerFcmToken());
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

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

    // Configuración general para las plataformas soportadas
    const initSettings = InitializationSettings(
      android: androidInit,
      // iOS / macOS usan configuraciones específicas aquí si las requieres luego
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload == null) return;
        _navigateToEmergency(jsonDecode(payload) as Map<String, dynamic>);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  Future<void> _requestPermissions() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  Future<void> _registerFcmToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;

      final vendorId = await _getVendorIdIfAny();
      if (vendorId == null) return;

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
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
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