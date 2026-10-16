# areaguardian

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Aviso manual al contacto de emergencia

Al activarse una emergencia, la pantalla de seguridad ofrece **Abrir SMS para
enviar**. La app abre el compositor de mensajes del teléfono con el número y el
texto completo, incluida la ubicación de Google Maps. El usuario debe revisar y
pulsar Enviar; AreaGuardian no envía SMS automáticamente ni requiere secretos
de Twilio.

Las notificaciones FCM a puestos cercanos continúan siendo automáticas. La
pantalla mantiene los 20 segundos para cancelar la alarma. La Function de
contacto solo registra `contactAlertStatus: manual` y no contacta al destinatario.

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
