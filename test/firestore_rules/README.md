# Firestore rules tests

Install the test dependencies once:

```powershell
npm install --prefix test/firestore_rules
```

Run the tests against the Firestore emulator:

```powershell
firebase emulators:exec --project demo-area-guardian-rules --only firestore "npm --prefix test/firestore_rules test"
```
