import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";

export const deleteAccountAndData = onCall(
  {region: "southamerica-east1", timeoutSeconds: 300},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
    }

    const db = getFirestore();
    try {
      let emergencies;
      do {
        emergencies = await db.collection("emergencies")
          .where("userId", "==", uid)
          .limit(100)
          .get();
        await Promise.all(
          emergencies.docs.map((document) =>
            db.recursiveDelete(document.ref)
          ),
        );
      } while (!emergencies.empty);

      await db.recursiveDelete(db.collection("users").doc(uid));
      await db.recursiveDelete(db.collection("vendors").doc(uid));
      await db.recursiveDelete(db.collection("public_vendors").doc(uid));
      await getStorage().bucket().deleteFiles({
        prefix: `profile_photos/${uid}/`,
      });
      await getAuth().deleteUser(uid);
      return {deleted: true};
    } catch (error) {
      logger.error("No se pudo completar la eliminación de la cuenta.", {
        uid,
        error,
      });
      throw new HttpsError(
        "internal",
        "No se pudieron eliminar todos los datos. Intenta de nuevo.",
      );
    }
  },
);
