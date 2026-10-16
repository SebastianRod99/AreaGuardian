# SMS de emergencia

`sendEmergencySms` is a callable Cloud Function v2 in `southamerica-east1`.
It reads `users/{uid}.emergencyContact` on the server and claims each active
emergency once before calling Twilio. Configure `TWILIO_SENDER` with either a
Twilio sender number or a Messaging Service SID.

Set secrets without adding their values to the repository:

```powershell
firebase functions:secrets:set TWILIO_ACCOUNT_SID
firebase functions:secrets:set TWILIO_AUTH_TOKEN
firebase functions:secrets:set TWILIO_SENDER
```

Build and deploy after setting all three secrets:

```powershell
npm --prefix functions run build
firebase deploy --only firestore:rules,functions
```

The app waits 20 seconds before its automatic call. If the call fails, it opens
the device's SMS composer with the Colombian contact number and message filled
in; the user must press Send. No `SEND_SMS` Android permission is used.
