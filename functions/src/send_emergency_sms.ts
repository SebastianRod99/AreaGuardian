import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {defineSecret} from "firebase-functions/params";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import twilio from "twilio";

const twilioAccountSid = defineSecret("TWILIO_ACCOUNT_SID");
const twilioAuthToken = defineSecret("TWILIO_AUTH_TOKEN");
const twilioSender = defineSecret("TWILIO_SENDER");
const gracePeriodMs = 20_000;

const db = getFirestore();

type SmsClaim =
  | {
    kind: "claimed";
    phone: string;
    contactName: string;
    userName: string;
    emergency: FirebaseFirestore.DocumentData;
  }
  | {kind: "sent"; smsSid: string | null; contactName: string}
  | {kind: "failed"; message: string}
  | {kind: "inProgress"};

function parseColombianMobile(contact: string): string | null {
  const phone = contact.split("—").at(-1)?.trim() ?? "";
  const digits = phone.replace(/\D/g, "");

  if (/^3\d{9}$/.test(digits)) return `+57${digits}`;
  if (/^573\d{9}$/.test(digits)) return `+${digits}`;
  return null;
}

function contactName(contact: string): string {
  const name = contact.split("—")[0]?.trim();
  return name || "tu contacto de emergencia";
}

function safeError(error: unknown): string {
  if (
    error instanceof Error &&
    /timed?\s*out|timeout/i.test(error.message)
  ) {
    return "Twilio request timed out.";
  }
  if (typeof error === "object" && error !== null && "code" in error) {
    const code = error.code;
    if (typeof code === "number" || typeof code === "string") {
      return `Twilio error ${String(code).slice(0, 40)}.`;
    }
  }
  return "Twilio request failed.";
}

export const sendEmergencySms = onCall(
  {
    region: "southamerica-east1",
    timeoutSeconds: 15,
    secrets: [twilioAccountSid, twilioAuthToken, twilioSender],
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
    }

    const emergencyId = request.data?.emergencyId;
    if (
      typeof emergencyId !== "string" ||
      emergencyId.length === 0 ||
      emergencyId.length > 128 ||
      emergencyId.includes("/")
    ) {
      throw new HttpsError("invalid-argument", "La emergencia no es válida.");
    }
    if (
      request.data?.sendNow !== undefined &&
      typeof request.data.sendNow !== "boolean"
    ) {
      throw new HttpsError("invalid-argument", "La opción de envío no es válida.");
    }

    const emergencyRef = db.collection("emergencies").doc(emergencyId);
    const userRef = db.collection("users").doc(uid);
    const sendNow = request.data?.sendNow === true;

    const claim = await db.runTransaction<SmsClaim>(async (transaction) => {
      const emergencySnapshot = await transaction.get(emergencyRef);
      if (!emergencySnapshot.exists) {
        throw new HttpsError("not-found", "La emergencia no existe.");
      }
      const emergency = emergencySnapshot.data()!;
      if (emergency.userId !== uid) {
        throw new HttpsError(
          "permission-denied",
          "La emergencia no pertenece a este usuario.",
        );
      }
      if (emergency.status !== "active") {
        throw new HttpsError(
          "failed-precondition",
          "La emergencia ya no está activa.",
        );
      }
      if (emergency.isTest === true) {
        throw new HttpsError(
          "failed-precondition",
          "Los simulacros no envían SMS.",
        );
      }

      const existingStatus =
        typeof emergency.smsStatus === "string" ? emergency.smsStatus : "pending";
      if (existingStatus === "sent") {
        return {
          kind: "sent",
          smsSid: typeof emergency.smsSid === "string" ? emergency.smsSid : null,
          contactName: "tu contacto de emergencia",
        };
      }
      if (existingStatus === "failed") {
        return {
          kind: "failed",
          message: "El envío automático ya falló para esta emergencia.",
        };
      }
      if (emergency.smsClaimedAt != null) return {kind: "inProgress"};

      if (
        !sendNow &&
        (!(emergency.timestamp instanceof Timestamp) ||
          emergency.timestamp.toMillis() + gracePeriodMs > Date.now())
      ) {
        throw new HttpsError(
          "failed-precondition",
          "El período de gracia todavía no ha terminado.",
        );
      }

      const userSnapshot = await transaction.get(userRef);
      if (!userSnapshot.exists) {
        throw new HttpsError(
          "failed-precondition",
          "No existe el perfil del usuario.",
        );
      }
      const rawContact = userSnapshot.get("emergencyContact");
      if (typeof rawContact !== "string" || rawContact.trim().length === 0) {
        transaction.update(emergencyRef, {
          smsStatus: "failed",
          smsError: "El usuario no tiene contacto de emergencia configurado.",
        });
        return {
          kind: "failed",
          message: "No tienes un contacto de emergencia configurado.",
        };
      }

      const phone = parseColombianMobile(rawContact);
      if (!phone) {
        transaction.update(emergencyRef, {
          smsStatus: "failed",
          smsError: "El teléfono de emergencia no es un celular colombiano válido.",
        });
        return {
          kind: "failed",
          message: "El teléfono de emergencia no es un celular colombiano válido.",
        };
      }

      transaction.update(emergencyRef, {
        smsStatus: "pending",
        smsClaimedAt: FieldValue.serverTimestamp(),
        smsError: FieldValue.delete(),
      });
      return {
        kind: "claimed",
        phone,
        contactName: contactName(rawContact),
        userName:
          typeof userSnapshot.get("name") === "string"
            ? userSnapshot.get("name")
            : "",
        emergency,
      };
    });

    if (claim.kind === "sent") {
      return {
        status: "sent",
        smsSid: claim.smsSid,
        contactName: claim.contactName,
      };
    }
    if (claim.kind === "failed") {
      throw new HttpsError("failed-precondition", claim.message);
    }
    if (claim.kind === "inProgress") {
      throw new HttpsError(
        "already-exists",
        "Ya se está procesando el SMS de esta emergencia.",
      );
    }

    const emergency = claim.emergency;
    const mapUrl = `https://maps.google.com/?q=${emergency.latitude},${emergency.longitude}`;
    const sanitizedUserName =
      typeof claim.userName === "string"
        ? claim.userName
          .replace(/[\p{Extended_Pictographic}\uFE0F\u200D]/gu, "")
          .replace(/\s+/g, " ")
          .trim()
          .slice(0, 60)
        : "";
    const userName = sanitizedUserName || "Una persona";
    const body =
      `AreaGuardian: ${userName} activó una alerta. ` +
      "Verifica la situación y llama al 123 si requiere ayuda. " +
      `Ubicación: ${mapUrl}`;

    try {
      const accountSid = twilioAccountSid.value().trim();
      const authToken = twilioAuthToken.value().trim();
      const sender = twilioSender.value().trim();
      if (!accountSid || !authToken || !sender) {
        throw new Error("Falta configurar uno o más secretos de Twilio.");
      }

      const client = twilio(accountSid, authToken, {
        timeout: 8_000,
        autoRetry: false,
      });
      const message = await client.messages.create(
        sender.startsWith("MG")
          ? {messagingServiceSid: sender, to: claim.phone, body}
          : {from: sender, to: claim.phone, body},
      );

      try {
        await emergencyRef.update({
          smsStatus: "sent",
          smsSid: message.sid,
          smsError: FieldValue.delete(),
          smsSentAt: FieldValue.serverTimestamp(),
        });
      } catch (error) {
        logger.error("SMS enviado pero no se pudo guardar su estado.", {
          emergencyId,
          error: safeError(error),
        });
      }

      return {
        status: "sent",
        smsSid: message.sid,
        contactName: claim.contactName,
      };
    } catch (error) {
      const errorMessage = safeError(error);
      try {
        await emergencyRef.update({
          smsStatus: "failed",
          smsError: errorMessage,
        });
      } catch (stateError) {
        logger.error("No se pudo guardar el fallo del SMS.", {
          emergencyId,
          error: safeError(stateError),
        });
      }
      logger.error("Falló el envío del SMS de emergencia.", {
        emergencyId,
        error: errorMessage,
      });
      throw new HttpsError(
        "internal",
        "No se pudo enviar el SMS automático.",
      );
    }
  },
);
