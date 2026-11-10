const {initializeApp, deleteApp} = require("firebase-admin/app");
const {FieldValue, Timestamp, getFirestore} =
  require("firebase-admin/firestore");

const projectId = "demo-area-guardian-functions";
const app = initializeApp({projectId});
const db = getFirestore(app);
const suffix = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
const emergencyId = `emulator-${suffix}`;
const location = {latitude: 4.65, longitude: -74.05};
const recentLocationTime = Timestamp.now();
const emergencyRef = db.collection("emergencies").doc(emergencyId);

async function waitForRecipients() {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const snapshot = await emergencyRef.get();
    const recipientIds = snapshot.data()?.notifiedUserIds;
    if (
      snapshot.data()?.alertVisible === true &&
      Array.isArray(recipientIds) &&
      recipientIds.includes(`nearby-${suffix}`)
    ) {
      return recipientIds;
    }
    await new Promise((resolve) => setTimeout(resolve, 300));
  }
  throw new Error("Functions emulator did not write notifiedUserIds in time");
}

async function main() {
  const userRecords = [
    {
      id: `nearby-${suffix}`,
      latitude: location.latitude + 0.001,
      longitude: location.longitude,
      lastKnownLocationAt: recentLocationTime,
    },
    {
      id: `far-${suffix}`,
      latitude: location.latitude + 0.01,
      longitude: location.longitude,
      lastKnownLocationAt: recentLocationTime,
    },
    {
      id: `stale-${suffix}`,
      latitude: location.latitude,
      longitude: location.longitude,
      lastKnownLocationAt: Timestamp.fromMillis(
        Date.now() - 25 * 60 * 60_000,
      ),
    },
    {
      id: `creator-${suffix}`,
      latitude: location.latitude,
      longitude: location.longitude,
      lastKnownLocationAt: recentLocationTime,
    },
  ];

  await Promise.all(userRecords.map((user) =>
    db.collection("users").doc(user.id).set({
      lastKnownLatitude: user.latitude,
      lastKnownLongitude: user.longitude,
      lastKnownLocationAt: user.lastKnownLocationAt,
    })
  ));
  await emergencyRef.set({
    id: emergencyId,
    userId: `creator-${suffix}`,
    userName: "Emulator test",
    role: "client",
    shopName: "Vecino",
    latitude: location.latitude,
    longitude: location.longitude,
    timestamp: FieldValue.serverTimestamp(),
    status: "active",
    isTest: false,
  });

  const recipientIds = await waitForRecipients();
  const expected = `nearby-${suffix}`;
  if (
    recipientIds.length !== 2 ||
    !recipientIds.includes(expected) ||
    recipientIds.includes(`far-${suffix}`) ||
    recipientIds.includes(`stale-${suffix}`) ||
    !recipientIds.includes(`creator-${suffix}`)
  ) {
    throw new Error(
      `Unexpected notifiedUserIds: ${JSON.stringify(recipientIds)}`,
    );
  }

  console.log("Functions emulator wrote the expected nearby user recipient.");
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await deleteApp(app);
  });
