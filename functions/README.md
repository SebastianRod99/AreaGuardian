# Cloud Functions

Las funciones gestionan las notificaciones FCM de alertas cercanas y las
encuestas posteriores a una emergencia. El SMS se prepara únicamente en la
aplicación de mensajes del dispositivo; no hay una función ni un servicio
externo de envío de SMS.

Para validar el código local:

```powershell
npm --prefix functions run build
```
