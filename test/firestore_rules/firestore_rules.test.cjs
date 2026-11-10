const fs = require("node:fs");
const path = require("node:path");
const { after, before, beforeEach, test } = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  deleteDoc,
  collection,
  doc,
  getDocs,
  getDoc,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} = require("firebase/firestore");
const { ref, uploadBytes } = require("firebase/storage");

const projectId = "demo-area-guardian-rules";
let testEnvironment;

const userProfile = (uid, overrides = {}) => ({
  id: uid,
  name: "Test User",
  email: `${uid}@example.test`,
  phone: "",
  isVendor: false,
  latitude: null,
  longitude: null,
  lastSeen: null,
  ...overrides,
});

const vendorProfile = (uid) => ({
  id: uid,
  userId: uid,
  shopName: "Test Shop",
  address: "Test Address",
  vendorName: "Test Vendor",
  category: "General",
  latitude: 4.65,
  longitude: -74.05,
  nequiNumber: "",
  daviplataNumber: "",
  llaveNumber: "",
  catalog: [],
  isActive: false,
  lastSeen: null,
});

const publicVendorProfile = (vendor) => ({
  id: vendor.id,
  shopName: vendor.shopName,
  address: vendor.address,
  latitude: vendor.latitude,
  longitude: vendor.longitude,
  currentLatitude: vendor.currentLatitude ?? null,
  currentLongitude: vendor.currentLongitude ?? null,
  lastLocationUpdate: vendor.lastLocationUpdate ?? null,
  isActive: vendor.isActive,
  nequiNumber: vendor.nequiNumber,
  daviplataNumber: vendor.daviplataNumber,
  llaveNumber: vendor.llaveNumber,
  catalog: vendor.catalog,
});

function appNearbyEmergencyQuery(db, userId) {
  const clauses = [
    where("status", "==", "active"),
    where("isTest", "==", false),
    where("notifiedUserIds", "array-contains", userId),
    where("timestamp", ">=", Timestamp.fromMillis(Date.now() - 20 * 60_000)),
    where("timestamp", "<=", Timestamp.now()),
  ];
  return query(collection(db, "emergencies"), ...clauses);
}

async function seed(pathSegments, data) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), ...pathSegments), data);
  });
}

before(async () => {
  const rules = fs.readFileSync(
    path.join(__dirname, "..", "..", "firestore.rules"),
    "utf8",
  );
  const storageRules = fs.readFileSync(
    path.join(__dirname, "..", "..", "storage.rules"),
    "utf8",
  );
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
    storage: { rules: storageRules },
  });
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
  await testEnvironment.clearStorage();
});

after(async () => {
  await testEnvironment?.cleanup();
});

test("new users can read a missing profile and create their own profile", async () => {
  const alice = testEnvironment.authenticatedContext("alice").firestore();
  const ownProfile = doc(alice, "users", "alice");
  const missingProfile = await assertSucceeds(getDoc(ownProfile));

  if (missingProfile.exists()) {
    throw new Error("Expected the new user's profile not to exist yet");
  }

  await assertSucceeds(setDoc(ownProfile, userProfile("alice")));
  await assertSucceeds(updateDoc(ownProfile, { phone: "555-0100" }));
  const createdProfile = await assertSucceeds(getDoc(ownProfile));
  if (!createdProfile.exists()) {
    throw new Error("Expected the user's profile to exist after creation");
  }

  const bob = testEnvironment.authenticatedContext("bob").firestore();
  await assertFails(getDoc(doc(bob, "users", "alice")));
  await assertFails(
    updateDoc(doc(bob, "users", "alice"), { phone: "555-0199" }),
  );
});

test("app registration, session restore, location, and vendor projection work", async () => {
  const alice = testEnvironment.authenticatedContext("alice").firestore();
  const userRef = doc(alice, "users", "alice");
  const vendorRef = doc(alice, "vendors", "alice");

  await assertSucceeds(
    setDoc(
      userRef,
      userProfile("alice", { isVendor: true, vendorId: "alice" }),
    ),
  );
  await assertSucceeds(setDoc(vendorRef, vendorProfile("alice")));

  await assertSucceeds(getDoc(userRef));
  await assertSucceeds(getDoc(vendorRef));
  await assertSucceeds(
    updateDoc(userRef, {
      lastLoginAt: serverTimestamp(),
      appVersion: "1.0.0+1",
      consentVersion: "1.0",
      consentAcceptedAt: serverTimestamp(),
      analyticsConsent: false,
    }),
  );
  await assertSucceeds(
    updateDoc(userRef, {
      lastKnownLatitude: 4.65,
      lastKnownLongitude: -74.05,
      lastKnownLocationAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(vendorRef, {
      currentLatitude: 4.65,
      currentLongitude: -74.05,
      lastLocationUpdate: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(vendorRef, {
      isActive: true,
      lastSeen: serverTimestamp(),
    }),
  );

  const vendor = (await getDoc(vendorRef)).data();
  await assertSucceeds(
    setDoc(
      doc(alice, "public_vendors", "alice"),
      publicVendorProfile(vendor),
    ),
  );
  const bob = testEnvironment.authenticatedContext("bob").firestore();
  await assertSucceeds(getDoc(doc(bob, "public_vendors", "alice")));
});

test("legacy user and vendor documents remain editable without changing extra fields", async () => {
  const legacyUser = userProfile("legacy", {
    role: "client",
    createdAt: Timestamp.fromMillis(Date.now() - 86_400_000),
    legacyPreference: "kept",
  });
  const legacyVendor = {
    ...vendorProfile("legacy-vendor"),
    lastSeen: "2024-01-02T03:04:05.000Z",
    lastLocationUpdate: "2024-01-02T03:04:05.000Z",
    legacyOwnerField: "kept",
  };
  await seed(["users", "legacy"], legacyUser);
  await seed(["users", "legacy-vendor"], userProfile("legacy-vendor", {
    isVendor: true,
    vendorId: "legacy-vendor",
  }));
  await seed(["vendors", "legacy-vendor"], legacyVendor);

  const legacy = testEnvironment.authenticatedContext("legacy").firestore();
  await assertSucceeds(
    updateDoc(doc(legacy, "users", "legacy"), {
      lastLoginAt: serverTimestamp(),
      appVersion: "1.0.0+1",
      lastKnownLatitude: 4.65,
      lastKnownLongitude: -74.05,
      lastKnownLocationAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(legacy, "users", "legacy"), { legacyPreference: "changed" }),
  );

  const vendor = testEnvironment.authenticatedContext(
    "legacy-vendor",
  ).firestore();
  const vendorRef = doc(vendor, "vendors", "legacy-vendor");
  await assertSucceeds(
    setDoc(
      vendorRef,
      {
        id: "legacy-vendor",
        userId: "legacy-vendor",
        shopName: "Updated Shop",
        address: "Updated Address",
        vendorName: "Updated Owner",
        category: "General",
        latitude: 4.66,
        longitude: -74.06,
      },
      { merge: true },
    ),
  );
  await assertSucceeds(
    updateDoc(vendorRef, {
      currentLatitude: 4.65,
      currentLongitude: -74.05,
      lastLocationUpdate: serverTimestamp(),
      isActive: true,
      lastSeen: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(vendorRef, { legacyOwnerField: "changed" }),
  );

  const updatedUser = (await getDoc(doc(legacy, "users", "legacy"))).data();
  const updatedVendor = (await getDoc(vendorRef)).data();
  if (
    updatedUser.legacyPreference !== "kept" ||
    updatedVendor.legacyOwnerField !== "kept"
  ) {
    throw new Error("Expected unmodified legacy fields to remain in place");
  }
});

test("vendors can read and write only their own vendor document", async () => {
  const aliceVendor = vendorProfile("alice");
  await seed(["users", "alice"], userProfile("alice", {
    isVendor: true,
    vendorId: "alice",
  }));
  await seed(["vendors", "alice"], aliceVendor);

  const alice = testEnvironment.authenticatedContext("alice").firestore();
  const ownVendor = doc(alice, "vendors", "alice");
  await assertSucceeds(getDoc(ownVendor));
  await assertSucceeds(updateDoc(ownVendor, { address: "Updated Address" }));

  const bob = testEnvironment.authenticatedContext("bob").firestore();
  await assertFails(getDoc(doc(bob, "vendors", "alice")));
  await assertFails(
    updateDoc(doc(bob, "vendors", "alice"), { address: "Hijacked" }),
  );

  await seed(["users", "charlie"], userProfile("charlie", {
    isVendor: true,
    vendorId: "charlie",
  }));
  const charlie = testEnvironment.authenticatedContext("charlie").firestore();
  await assertSucceeds(
    setDoc(doc(charlie, "vendors", "charlie"), vendorProfile("charlie")),
  );
  await assertFails(
    setDoc(doc(bob, "vendors", "alice"), vendorProfile("alice")),
  );
});

test("public vendors are readable by authenticated users and writable by owners", async () => {
  const vendor = vendorProfile("alice");
  await seed(["vendors", "alice"], vendor);

  const alice = testEnvironment.authenticatedContext("alice").firestore();
  const publicVendor = doc(alice, "public_vendors", "alice");
  await assertSucceeds(setDoc(publicVendor, publicVendorProfile(vendor)));
  await assertSucceeds(getDoc(publicVendor));
  await assertSucceeds(
    updateDoc(publicVendor, { address: "Test Address" }),
  );
  await assertSucceeds(deleteDoc(publicVendor));

  const bob = testEnvironment.authenticatedContext("bob").firestore();
  await assertSucceeds(getDoc(doc(bob, "public_vendors", "alice")));
  await assertFails(
    setDoc(
      doc(bob, "public_vendors", "alice"),
      publicVendorProfile(vendor),
    ),
  );
  await assertFails(
    updateDoc(doc(bob, "public_vendors", "alice"), {
      address: "Unauthorized",
    }),
  );

  const anonymous = testEnvironment.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anonymous, "public_vendors", "alice")));
});

test("app emergency creation, cancellation, resolution, and survey use server timestamps", async () => {
  const alice = testEnvironment.authenticatedContext("alice").firestore();
  const userRef = doc(alice, "users", "alice");
  await assertSucceeds(setDoc(userRef, userProfile("alice")));

  async function createEmergency(emergencyId) {
    const emergencyRef = doc(alice, "emergencies", emergencyId);
    await assertSucceeds(
      runTransaction(alice, async (transaction) => {
        await transaction.get(userRef);
        transaction.set(emergencyRef, {
          id: emergencyId,
          userId: "alice",
          userName: "Test User",
          role: "client",
          shopName: "Vecino",
          latitude: 4.65,
          longitude: -74.05,
          timestamp: serverTimestamp(),
          status: "active",
          isTest: false,
        });
        transaction.update(userRef, { activeEmergencyId: emergencyId });
      }),
    );
    const savedEmergency = (await getDoc(emergencyRef)).data();
    if (!(savedEmergency.timestamp instanceof Timestamp)) {
      throw new Error("Expected the emergency timestamp to be server time");
    }
    for (const serverOnlyField of [
      "alertVisible",
      "notifiedUserIds",
      "notifiedVendorIds",
      "surveyNotificationStatus",
    ]) {
      if (serverOnlyField in savedEmergency) {
        throw new Error(`Unexpected client field: ${serverOnlyField}`);
      }
    }
    return emergencyRef;
  }

  async function closeEmergency(emergencyRef, status) {
    await assertSucceeds(
      runTransaction(alice, async (transaction) => {
        await transaction.get(emergencyRef);
        await transaction.get(userRef);
        transaction.update(emergencyRef, {
          status,
          resolvedAt: serverTimestamp(),
        });
        transaction.update(userRef, {
          activeEmergencyId: null,
        });
      }),
    );
    const closedEmergency = (await getDoc(emergencyRef)).data();
    if (!(closedEmergency.resolvedAt instanceof Timestamp)) {
      throw new Error("Expected resolvedAt to be server time");
    }
  }

  const cancelled = await createEmergency("cancelled");
  await closeEmergency(cancelled, "cancelled");

  const resolved = await createEmergency("resolved");
  await closeEmergency(resolved, "resolved");

  const surveyed = await createEmergency("surveyed");
  await assertSucceeds(
    runTransaction(alice, async (transaction) => {
      await transaction.get(surveyed);
      transaction.update(surveyed, {
        surveyFeedback: {
          wasSafe: true,
          falseAlarm: false,
          submittedAt: serverTimestamp(),
        },
      });
    }),
  );
  const survey = (await getDoc(surveyed)).data().surveyFeedback;
  if (!(survey.submittedAt instanceof Timestamp)) {
    throw new Error("Expected submittedAt to be server time");
  }
});

test("nearby alert query returns only server-notified active emergencies", async () => {
  const emergency = {
    userName: "Test User",
    role: "client",
    shopName: "Vecino",
    latitude: 4.65,
    longitude: -74.05,
    status: "active",
    isTest: false,
    alertVisible: true,
  };
  await seed(["emergencies", "nearby"], {
    ...emergency,
    id: "nearby",
    userId: "alice",
    notifiedUserIds: ["bob"],
    timestamp: Timestamp.fromMillis(Date.now() - 60_000),
  });
  await seed(["emergencies", "creator"], {
    ...emergency,
    id: "creator",
    userId: "carol",
    notifiedUserIds: ["carol"],
    timestamp: Timestamp.fromMillis(Date.now() - 60_000),
  });
  const bob = testEnvironment.authenticatedContext("bob").firestore();
  await assertSucceeds(getDoc(doc(bob, "emergencies", "nearby")));
  const results = await assertSucceeds(getDocs(appNearbyEmergencyQuery(bob, "bob")));
  if (results.docs.length !== 1 || results.docs[0].id !== "nearby") {
    throw new Error("Expected only the emergency whose server list includes bob");
  }

  const stranger = testEnvironment.authenticatedContext("dave").firestore();
  await assertFails(getDoc(doc(stranger, "emergencies", "nearby")));
  await assertFails(getDocs(query(
    collection(stranger, "emergencies"),
    where("status", "==", "active"),
    where("isTest", "==", false),
    where("timestamp", ">=", Timestamp.fromMillis(Date.now() - 20 * 60_000)),
    where("timestamp", "<=", Timestamp.now()),
  )));

  const creator = testEnvironment.authenticatedContext("carol").firestore();
  await assertSucceeds(getDoc(doc(creator, "emergencies", "creator")));
  const creatorResults = await assertSucceeds(
    getDocs(appNearbyEmergencyQuery(creator, "carol")),
  );
  if (
    creatorResults.docs.length !== 1 ||
    creatorResults.docs[0].id !== "creator"
  ) {
    throw new Error("Expected the creator to see their own active emergency");
  }
});

test("test and cancelled emergencies cannot be submitted as surveys", async () => {
  await seed(["emergencies", "test-emergency"], {
    userId: "alice",
    status: "active",
    isTest: true,
  });
  await seed(["emergencies", "cancelled-emergency"], {
    userId: "alice",
    status: "cancelled",
    isTest: false,
  });
  await seed(["emergencies", "valid-emergency"], {
    userId: "alice",
    status: "active",
    isTest: false,
  });

  const alice = testEnvironment.authenticatedContext("alice").firestore();
  const feedback = {
    wasSafe: true,
    falseAlarm: false,
    submittedAt: serverTimestamp(),
  };

  await assertFails(
    updateDoc(doc(alice, "emergencies", "test-emergency"), {
      surveyFeedback: feedback,
    }),
  );
  await assertFails(
    updateDoc(doc(alice, "emergencies", "cancelled-emergency"), {
      surveyFeedback: feedback,
    }),
  );
  await assertSucceeds(
    updateDoc(doc(alice, "emergencies", "valid-emergency"), {
      surveyFeedback: feedback,
    }),
  );
});

test("profile photos accept only small images uploaded by their owner", async () => {
  const alice = testEnvironment.authenticatedContext("alice").storage();
  const ownPhoto = ref(alice, "profile_photos/alice/profile.jpg");
  await assertSucceeds(
    uploadBytes(ownPhoto, new Uint8Array(1024), {
      contentType: "image/jpeg",
    }),
  );

  const bob = testEnvironment.authenticatedContext("bob").storage();
  await assertFails(
    uploadBytes(
      ref(bob, "profile_photos/alice/profile.jpg"),
      new Uint8Array(1024),
      { contentType: "image/jpeg" },
    ),
  );
  await assertFails(
    uploadBytes(
      ref(alice, "profile_photos/alice/profile.jpg"),
      new Uint8Array(5 * 1024 * 1024),
      { contentType: "image/jpeg" },
    ),
  );
  await assertFails(
    uploadBytes(
      ref(alice, "profile_photos/alice/profile.jpg"),
      new Uint8Array(1024),
      { contentType: "text/plain" },
    ),
  );
});
