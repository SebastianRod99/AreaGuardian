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
  doc,
  getDoc,
  setDoc,
  updateDoc,
} = require("firebase/firestore");

const projectId = "demo-area-guardian-rules";
let testEnvironment;

const userProfile = (uid, overrides = {}) => ({
  id: uid,
  name: "Test User",
  email: `${uid}@example.test`,
  phone: "",
  isVendor: false,
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
});

const publicVendorProfile = (vendor) => ({
  id: vendor.id,
  shopName: vendor.shopName,
  address: vendor.address,
  latitude: vendor.latitude,
  longitude: vendor.longitude,
  currentLatitude: null,
  currentLongitude: null,
  lastLocationUpdate: null,
  isActive: vendor.isActive,
  nequiNumber: vendor.nequiNumber,
  daviplataNumber: vendor.daviplataNumber,
  llaveNumber: vendor.llaveNumber,
  catalog: vendor.catalog,
});

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
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
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
