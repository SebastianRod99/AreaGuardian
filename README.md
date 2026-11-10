# areaguardian

Aplicación Flutter de seguridad y alertas comunitarias.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## SMS de emergencia

Después de confirmar una emergencia, la app da 20 segundos para cancelarla y
abre el compositor de SMS del teléfono con el número y la ubicación
prellenados. El mensaje no se envía automáticamente: el usuario debe revisar
el destinatario y pulsar Enviar. AreaGuardian no envía SMS mediante servicios
externos ni requiere permiso Android `SEND_SMS`.

Las notificaciones FCM a puestos cercanos son automáticas. Los simulacros y las
emergencias canceladas no deben generar SMS ni encuestas.

## Encuesta post-emergencia

`sendPostEmergencySurveyReminders` consulta cada minuto las emergencias con
`surveyNotificationStatus: pending` y envía el push al usuario cuando han pasado
10 minutos desde el `timestamp` de Firestore. Por la cadencia de Cloud Scheduler,
la entrega puede ocurrir hasta un minuto después del umbral. El dispositivo debe
haber iniciado sesión, concedido permiso de notificaciones y registrado su
token FCM en `users/{uid}.fcmToken`. Las respuestas se guardan en
`emergencies/{id}.surveyFeedback`; una falsa alarma cambia `status` a
`false_alarm` y libera el puntero de emergencia activo.

El despliegue del scheduler requiere que Google Cloud Scheduler esté habilitado
en el proyecto (puede requerir el plan Blaze). Despliega las Functions con:

```powershell
firebase deploy --only functions
```

## APK Android de release

Define primero el `applicationId` definitivo en
`android/app/build.gradle.kts` y registra en Firebase la app Android con ese
paquete. El firmado release usa `android/key.properties` (ignorado por Git):

```properties
storeFile=../ruta/local/a/release.jks
storePassword=...
keyAlias=...
keyPassword=...
```

`storeFile` puede ser una ruta absoluta o relativa a `android/`. El build
release falla si falta alguna propiedad o la keystore; nunca usa la clave debug.
Registra en Firebase las huellas SHA-1 y SHA-256 de esa keystore antes de probar
Google Sign-In.
