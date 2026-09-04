# iOS/TestFlight adaptation design

## Goal

Make the current Flutter app available to iPhone users as **圣经背诵**, without changing Android behavior, and prepare TestFlight beta distribution.

## Platform contract

Shared Flutter UI, SQLite data, scripture assets, and recitation logic remain shared. Android keeps APK update/download verification, MediaStore JSON export, APK QR creation, and exact-alarm behavior. iOS uses the standard document save UI and Darwin notifications.

The APK QR is Android-only. iOS must not render, save, or request photo access for it. A TestFlight action appears only after an HTTPS public TestFlight URL is supplied at build time. It opens that URL directly.

## iOS settings and validation

- Display name: `圣经背诵`.
- Bundle ID: `app.biblerecite`, subject to availability at Apple enrollment.
- Minimum OS: iOS 13.0.
- Add microphone permission text for offline recitation recording; no photo-library permission.
- Disable all in-app APK update checks on iOS because TestFlight handles updates.
- Test shared behavior in the simulator, then validate microphone, notifications, document export/import, and offline recognition through an external TestFlight tester.
