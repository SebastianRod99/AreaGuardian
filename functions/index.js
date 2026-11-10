const {
  onDocumentCreated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {initializeApp} = require("firebase-admin/app");
const {FieldValue, Timestamp, getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();
const emergencyChannelId = "emergency_alerts_channel_v2";
const emergencySoundName = "alarm";
const emergencySurveyDelayMs = 10 * 60_000;
const emergencyAlertRadiusMeters = 300;
const userLocationMaxAgeMs = 24 * 60 * 60_000;

async function claimVendorNotification(emergencyRef) {
  return db.runTransaction(async (transaction) => {
    const currentSnapshot = await transaction.get(emergencyRef);
    if (!currentSnapshot.exists) return null;

    const emergency = currentSnapshot.data();
    if (
      emergency.status !== "active" ||
      emergency.vendorNotificationStatus
    ) {
      return null;
    }

    transaction.update(emergencyRef, {
      vendorNotificationStatus: "sending",
      vendorNotificationStartedAt: FieldValue.serverTimestamp(),
      surveyNotificationStatus: "pending",
      alertVisible: true,
      notifiedUserIds: [],
      notifiedVendorIds: [],
    });
    return emergency;
  });
}

function distanceInMeters(latitudeA, longitudeA, latitudeB, longitudeB) {
  const earthRadius = 6371000;
  const radians = (degrees) => degrees * Math.PI / 180;
  const deltaLatitude = radians(latitudeB - latitudeA);
  const deltaLongitude = radians(longitudeB - longitudeA);
  const haversine = Math.sin(deltaLatitude / 2) ** 2 +
    Math.cos(radians(latitudeA)) *
    Math.cos(radians(latitudeB)) *
    Math.sin(deltaLongitude / 2) ** 2;
  return 2 * earthRadius * Math.asin(Math.sqrt(haversine));
}

function activeVendorCoordinates(vendor) {
  const hasFreshLocation =
    Number.isFinite(vendor.currentLatitude) &&
    Number.isFinite(vendor.currentLongitude) &&
    vendor.lastLocationUpdate instanceof Timestamp &&
    Date.now() - vendor.lastLocationUpdate.toMillis() <= 10 * 60_000;
  return hasFreshLocation ?
    [vendor.currentLatitude, vendor.currentLongitude] :
    [vendor.latitude, vendor.longitude];
}

function longitudeRanges(longitude, latitude, radiusMeters) {
  const longitudeScale = Math.abs(Math.cos(latitude * Math.PI / 180));
  const delta = longitudeScale < 1e-6 ?
    180 :
    Math.min(radiusMeters / (111320 * longitudeScale), 180);
  if (delta >= 180) return [{min: -180, max: 180}];

  const min = longitude - delta;
  const max = longitude + delta;
  if (min < -180) {
    return [
      {min: -180, max},
      {min: min + 360, max: 180},
    ];
  }
  if (max > 180) {
    return [
      {min: -180, max: max - 360},
      {min, max: 180},
    ];
  }
  return [{min, max}];
}

async function findNearbyUserIds(emergency) {
  const latitudeDelta = emergencyAlertRadiusMeters / 111320;
  const minLatitude = Math.max(-90, emergency.latitude - latitudeDelta);
  const maxLatitude = Math.min(90, emergency.latitude + latitudeDelta);
  const latitude = emergency.latitude;
  const longitude = emergency.longitude;
  const minLocationTime = Timestamp.fromMillis(Date.now() - userLocationMaxAgeMs);
  const candidates = new Map();

  for (const range of longitudeRanges(
    longitude,
    latitude,
    emergencyAlertRadiusMeters,
  )) {
    const snapshot = await db.collection("users")
      .where("lastKnownLatitude", ">=", minLatitude)
      .where("lastKnownLatitude", "<=", maxLatitude)
      .where("lastKnownLongitude", ">=", range.min)
      .where("lastKnownLongitude", "<=", range.max)
      .get();
    snapshot.docs.forEach((user) => candidates.set(user.id, user.data()));
  }

  const recipientIds = new Set([emergency.userId]);
  [...candidates.entries()]
    .filter(([userId, user]) => {
      if (
        !Number.isFinite(user.lastKnownLatitude) ||
        !Number.isFinite(user.lastKnownLongitude) ||
        !(user.lastKnownLocationAt instanceof Timestamp) ||
        user.lastKnownLocationAt.toMillis() < minLocationTime.toMillis() ||
        user.lastKnownLocationAt.toMillis() > Date.now()
      ) {
        return false;
      }
      return distanceInMeters(
        latitude,
        longitude,
        user.lastKnownLatitude,
        user.lastKnownLongitude,
      ) <= emergencyAlertRadiusMeters;
    })
    .forEach(([userId]) => recipientIds.add(userId));
  return [...recipientIds];
}

async function findNearbyVendorIds(emergency) {
  const snapshot = await db.collection("public_vendors")
    .where("isActive", "==", true)
    .get();

  return snapshot.docs
    .filter((doc) => {
      const vendor = doc.data();
      const [latitude, longitude] = activeVendorCoordinates(vendor);
      const distance = distanceInMeters(
        emergency.latitude,
        emergency.longitude,
        Number(latitude || 0),
        Number(longitude || 0),
      );
      return doc.id !== emergency.userId &&
        distance <= emergencyAlertRadiusMeters;
    })
    .map((doc) => doc.id);
}

function isValidEmergency(emergency) {
  return emergency &&
    typeof emergency.isTest === "boolean" &&
    (emergency.role === "vendor" || emergency.role === "client") &&
    Number.isFinite(Number(emergency.latitude)) &&
    Number.isFinite(Number(emergency.longitude)) &&
    Number(emergency.latitude) >= -90 &&
    Number(emergency.latitude) <= 90 &&
    Number(emergency.longitude) >= -180 &&
    Number(emergency.longitude) <= 180;
}

/**
 * Mantiene una proyeccion publica de cada puesto sin copiar datos personales
 * ni credenciales de pago desde 'vendors'.
 */
exports.syncPublicVendor = onDocumentWritten("vendors/{vendorId}", async (event) => {
  const after = event.data?.after;
  const publicVendor = db.collection("public_vendors").doc(event.params.vendorId);

  if (!after || !after.exists) {
    await publicVendor.delete();
    return;
  }

  const vendor = after.data();
  await publicVendor.set({
    id: event.params.vendorId,
    shopName: vendor.shopName || "",
    address: vendor.address || "",
    latitude: vendor.latitude || 0,
    longitude: vendor.longitude || 0,
    currentLatitude: vendor.currentLatitude ?? null,
    currentLongitude: vendor.currentLongitude ?? null,
    lastLocationUpdate: vendor.lastLocationUpdate ?? null,
    isActive: vendor.isActive === true,
    nequiNumber: vendor.nequiNumber || "",
    daviplataNumber: vendor.daviplataNumber || "",
    llaveNumber: vendor.llaveNumber || "",
    catalog: Array.isArray(vendor.catalog) ? vendor.catalog : [],
  });
});

/**
 * Se dispara cada vez que la app crea un documento en 'emergencies'
 * (FirestoreService.createEmergency, en el cliente Flutter).
 *
 * 1. Recalcula los puestos activos dentro de un radio de 300m para no
 *    confiar en una lista de destinatarios enviada por el cliente.
 * 2. Busca el token FCM de cada uno de esos puestos.
 * 3. Envía la notificación push — con "notification" para que Android la
 *    muestre automáticamente aunque la app esté en background o cerrada,
 *    usando el canal 'emergency_alerts_channel_v2' (declarado en
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
    const initialEmergency = snapshot.data();
    if (!isValidEmergency(initialEmergency)) {
      console.log(`Emergencia ${emergencyId}: payload inválido, se ignora.`);
      return;
    }
    if (initialEmergency.isTest === true) {
      await snapshot.ref.update({
        surveyNotificationStatus: "skipped",
        alertVisible: false,
        notifiedVendorIds: [],
        vendorNotificationStatus: "skipped",
        vendorNotificationCompletedAt: FieldValue.serverTimestamp(),
      });
      console.log(`Emergencia de prueba ${emergencyId}: no se notifica.`);
      return;
    }

    const emergency = await claimVendorNotification(snapshot.ref);
    if (!emergency) {
      console.log(`Emergencia ${emergencyId}: FCM ya reclamado; se ignora.`);
      return;
    }

    try {
    // La lista enviada por el cliente no se usa para autorizar destinatarios.
    // El backend calcula quién puede ver la alerta y notifica a los puestos.
    const userIds = await findNearbyUserIds(emergency);
    await snapshot.ref.update({notifiedUserIds: userIds});

    const vendorIds = await findNearbyVendorIds(emergency);

    if (vendorIds.length === 0) {
      await snapshot.ref.update({
        notifiedVendorIds: [],
        vendorNotificationStatus: "skipped",
        vendorNotificationCompletedAt: FieldValue.serverTimestamp(),
      });
      console.log(
        `Emergencia ${emergencyId}: sin puestos activos dentro del radio.`
      );
      return;
    }

    // Buscamos el token FCM de cada puesto notificado.
    const vendorDocs = await Promise.all(
      vendorIds.map((id) => db.collection("vendors").doc(id).get())
    );

    const recipients = vendorDocs
      .map((doc) => ({doc, token: doc.data()?.fcmToken}))
      .filter((recipient) =>
        recipient.doc.exists &&
        recipient.doc.data()?.isActive === true &&
        typeof recipient.token === "string" &&
        recipient.token.length > 0,
      );
    const recipientsByToken = new Map();
    recipients.forEach((recipient) => {
      const tokenRecipients = recipientsByToken.get(recipient.token) || [];
      tokenRecipients.push(recipient);
      recipientsByToken.set(recipient.token, tokenRecipients);
    });
    const tokens = [...recipientsByToken.keys()];

    if (tokens.length === 0) {
      await snapshot.ref.update({
        notifiedVendorIds: vendorIds,
        vendorNotificationStatus: "skipped",
        vendorNotificationCompletedAt: FieldValue.serverTimestamp(),
      });
      console.log(
        `Emergencia ${emergencyId}: ningún puesto activo tiene token FCM registrado todavía.`
      );
      return;
    }

    const sourceLabel = emergency.role === "vendor" && emergency.shopName
      ? emergency.shopName
      : "un vecino en la vía pública";
    const message = {
      notification: {
        title: `🚨 ¡Alerta en ${sourceLabel}!`,
        body: `${emergency.userName || "Un vecino"} necesita ayuda cerca de ti.`,
      },
      data: {
        emergencyId: emergencyId,
        latitude: String(emergency.latitude),
        longitude: String(emergency.longitude),
        role: emergency.role || "client",
        shopName: emergency.shopName || "Vecino",
        userName: emergency.userName || "Vecino",
      },
      android: {
        priority: "high",
        notification: {
          channelId: emergencyChannelId,
          sound: emergencySoundName,
          priority: "max",
          visibility: "public",
        },
      },
      tokens: tokens,
    };

    const response = await messaging.sendEachForMulticast(message);
    await snapshot.ref.update({
      notifiedVendorIds: vendorIds,
      vendorNotificationStatus: response.failureCount === 0 ? "sent" : "partial",
      vendorNotificationSuccessCount: response.successCount,
      vendorNotificationFailureCount: response.failureCount,
      vendorNotificationCompletedAt: FieldValue.serverTimestamp(),
    });
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
      await Promise.all(
        staleTokenIndexes.flatMap((i) =>
          recipientsByToken.get(tokens[i]).map((recipient) =>
            recipient.doc.ref.update({fcmToken: null})
          )
        )
      );
      console.log(`Se limpiaron ${staleTokenIndexes.length} tokens inválidos.`);
    }
    } catch (error) {
      try {
        await snapshot.ref.update({
          vendorNotificationStatus: "failed",
          vendorNotificationError: String(error.message || error).slice(0, 240),
          vendorNotificationCompletedAt: FieldValue.serverTimestamp(),
        });
      } catch (stateError) {
        console.error(
          `Emergencia ${emergencyId}: no se pudo guardar estado FCM.`,
          stateError,
        );
      }
      console.error(`Emergencia ${emergencyId}: fallo procesando FCM.`, error);
    }
  }
);

exports.expireEmergencyVisibility = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "America/Bogota",
    region: "southamerica-east1",
    maxInstances: 1,
  },
  async () => {
    const cutoff = Timestamp.fromMillis(Date.now() - 20 * 60_000);
    const expiredAlerts = await db.collection("emergencies")
      .where("status", "==", "active")
      .where("isTest", "==", false)
      .where("alertVisible", "==", true)
      .where("timestamp", "<=", cutoff)
      .get();
    if (expiredAlerts.empty) return;

    const writer = db.bulkWriter();
    expiredAlerts.docs.forEach((emergency) => {
      writer.update(emergency.ref, {
        alertVisible: false,
        notifiedUserIds: [],
      });
    });
    await writer.close();
    console.log(
      `Expired alert visibility for ${expiredAlerts.size} emergencies.`,
    );
  }
);

async function claimEmergencySurveyReminder(emergencyRef) {
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(emergencyRef);
    if (!snapshot.exists) return null;

    const emergency = snapshot.data();
    if (
      emergency.surveyNotificationStatus !== "pending" ||
      emergency.isTest === true ||
      emergency.status === "cancelled" ||
      !(emergency.timestamp instanceof Timestamp) ||
      emergency.timestamp.toMillis() + emergencySurveyDelayMs > Date.now() ||
      emergency.surveyFeedback
    ) {
      return null;
    }

    const attempt = Number(emergency.surveyNotificationAttempts || 0) + 1;
    transaction.update(emergencyRef, {
      surveyNotificationStatus: "sending",
      surveyNotificationAttempts: attempt,
      surveyNotificationStartedAt: FieldValue.serverTimestamp(),
    });
    return {emergency, attempt};
  });
}

exports.sendPostEmergencySurveyReminders = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "America/Bogota",
    region: "southamerica-east1",
    maxInstances: 1,
  },
  async () => {
    const pendingSnapshot = await db.collection("emergencies")
      .where("surveyNotificationStatus", "==", "pending")
      .get();
    const now = Timestamp.now();

    for (const emergencyDocument of pendingSnapshot.docs) {
      const emergencyRef = emergencyDocument.ref;
      const candidate = emergencyDocument.data();
      if (
        !(candidate.timestamp instanceof Timestamp) ||
        candidate.timestamp.toMillis() + emergencySurveyDelayMs > now.toMillis()
      ) {
        continue;
      }

      if (
        candidate.isTest === true ||
        candidate.status === "cancelled" ||
        candidate.surveyFeedback
      ) {
        await emergencyRef.update({
          surveyNotificationStatus: "skipped",
          surveyNotificationCompletedAt: FieldValue.serverTimestamp(),
        });
        continue;
      }

      if (Number(candidate.surveyNotificationAttempts || 0) >= 3) continue;

      if (typeof candidate.userId !== "string" || !candidate.userId) continue;
      const userRef = db.collection("users").doc(candidate.userId);
      const userSnapshot = await userRef.get();
      const token = userSnapshot.data()?.fcmToken;
      if (typeof token !== "string" || !token) {
        await emergencyRef.update({
          surveyNotificationStatus: "pending",
          surveyNotificationError: "El usuario no tiene token FCM disponible.",
        });
        console.log(
          `Encuesta de emergencia ${emergencyDocument.id}: sin token FCM; permanece pendiente.`,
        );
        continue;
      }

      const claim = await claimEmergencySurveyReminder(emergencyRef);
      if (!claim) continue;

      try {
        const latestSnapshot = await emergencyRef.get();
        if (!latestSnapshot.exists || latestSnapshot.data()?.surveyFeedback) {
          await emergencyRef.update({
            surveyNotificationStatus: "skipped",
            surveyNotificationCompletedAt: FieldValue.serverTimestamp(),
          });
          continue;
        }

        await messaging.send({
          token,
          notification: {
            title: "¿Cómo estás? Cuéntanos sobre la emergencia reciente",
            body: "Tu opinión nos ayuda a mejorar la respuesta de AreaGuardian.",
          },
          data: {
            type: "post_emergency_survey",
            emergencyId: emergencyDocument.id,
          },
          android: {priority: "high"},
        });
      } catch (error) {
        await emergencyRef.update({
          surveyNotificationStatus: "pending",
          surveyNotificationError: String(error.message || error).slice(0, 240),
          surveyNotificationCompletedAt: FieldValue.serverTimestamp(),
        });
        if (
          error.code === "messaging/registration-token-not-registered" ||
          error.code === "messaging/invalid-registration-token"
        ) {
          await userRef.update({fcmToken: FieldValue.delete()});
        }
        console.error(
          `Encuesta de emergencia ${emergencyDocument.id}: FCM falló (intento ${claim.attempt}).`,
          error,
        );

        continue;
      }

      try {
        await emergencyRef.update({
          surveyNotificationStatus: "sent",
          surveyNotificationSentAt: FieldValue.serverTimestamp(),
        });
      } catch (error) {
        console.error(
          `FCM aceptó la encuesta ${emergencyDocument.id}, pero no se pudo guardar el estado sent; no se repetirá el envío.`,
          error,
        );
      }
    }
  },
);

Object.assign(exports, require("./lib/delete_account"));