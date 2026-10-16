"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.deleteAccountAndData = void 0;
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const https_1 = require("firebase-functions/v2/https");
const firebase_functions_1 = require("firebase-functions");
exports.deleteAccountAndData = (0, https_1.onCall)({ region: "southamerica-east1", timeoutSeconds: 300 }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Debes iniciar sesión.");
    }
    const db = (0, firestore_1.getFirestore)();
    try {
        let emergencies;
        do {
            emergencies = await db.collection("emergencies")
                .where("userId", "==", uid)
                .limit(100)
                .get();
            await Promise.all(emergencies.docs.map((document) => db.recursiveDelete(document.ref)));
        } while (!emergencies.empty);
        await db.recursiveDelete(db.collection("users").doc(uid));
        await db.recursiveDelete(db.collection("vendors").doc(uid));
        await db.recursiveDelete(db.collection("public_vendors").doc(uid));
        await (0, storage_1.getStorage)().bucket().deleteFiles({
            prefix: `profile_photos/${uid}/`,
        });
        await (0, auth_1.getAuth)().deleteUser(uid);
        return { deleted: true };
    }
    catch (error) {
        firebase_functions_1.logger.error("No se pudo completar la eliminación de la cuenta.", {
            uid,
            error,
        });
        throw new https_1.HttpsError("internal", "No se pudieron eliminar todos los datos. Intenta de nuevo.");
    }
});
