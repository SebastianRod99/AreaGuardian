const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

/**
 * Se dispara cada vez que la app crea un documento en 'emergencies'
 * (FirestoreService.createEmergency, en el cliente Flutter).
 *
 * 1. Lee 'notifiedVendorIds' (ya calculado en el cliente con el radio de
 *    1000m) para saber a quién avisar.
 * 2. Busca el token FCM de cada uno de esos puestos.
 * 3. Envía la notificación push — con "notification" para que Android la
 *    muestre automáticamente aunque la app esté en background o cerrada,
 *    usando el canal 'emergency_alerts_channel' (declarado en
 *    AndroidManifest.xml y en notification_service.dart) para el sonido.
 */
exports.notifyNearbyVendorsOnEmergency = onDocumentCreated(
  "emergencies/{emergencyId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("Evento de emergencia sin datos, se ignora.");
      return;
    }

    const emergencyId = event.params.emergencyId;
    const emergency = snapshot.data();
    const vendorIds = emergency.notifiedVendorIds || [];

    if (vendorIds.length === 0) {
      console.log(
        `Emergencia ${emergencyId}: sin puestos activos dentro del radio.`
      );
      return;
    }

    // Buscamos el token FCM de cada puesto notificado.
    const vendorDocs = await Promise.all(
      vendorIds.map((id) => db.collection("vendors").doc(id).get())
    );

    const tokens = vendorDocs
      .filter((doc) => doc.exists && doc.data().fcmToken)
      .map((doc) => doc.data().fcmToken);

    if (tokens.length === 0) {
      console.log(
        `Emergencia ${emergencyId}: ningún puesto activo tiene token FCM registrado todavía.`
      );
      return;
    }

    const message = {
      notification: {
        title: "🚨 Emergencia cerca de tu puesto",
        body: `${emergency.userName || "Un vecino"} necesita ayuda cerca de ti.`,
      },
      data: {
        emergencyId: emergencyId,
        latitude: String(emergency.latitude),
        longitude: String(emergency.longitude),
      },
      android: {
        priority: "high",
        notification: {
          channelId: "emergency_alerts_channel",
          sound: "alarm",
          priority: "max",
        },
      },
      tokens: tokens,
    };

    const response = await messaging.sendEachForMulticast(message);
    console.log(
      `Emergencia ${emergencyId}: ${response.successCount} notificaciones enviadas, ` +
        `${response.failureCount} fallidas (de ${tokens.length} puestos).`
    );

    // Limpieza de tokens inválidos (app desinstalada, etc.) para no seguir
    // intentando enviarles en futuras emergencias.
    const staleTokenIndexes = [];
    response.responses.forEach((res, index) => {
      if (
        !res.success &&
        (res.error?.code === "messaging/registration-token-not-registered" ||
          res.error?.code === "messaging/invalid-registration-token")
      ) {
        staleTokenIndexes.push(index);
      }
    });

    if (staleTokenIndexes.length > 0) {
      const staleVendorDocs = vendorDocs.filter(
        (doc) => doc.exists && doc.data().fcmToken
      );
      await Promise.all(
        staleTokenIndexes.map((i) =>
          staleVendorDocs[i].ref.update({fcmToken: null})
        )
      );
      console.log(`Se limpiaron ${staleTokenIndexes.length} tokens inválidos.`);
    }
  }
);