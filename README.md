# iDecree, Stage 1

A Flutter app for reading your own quotes and declarations on a schedule.
This is **Stage 1: the personal app**. Circles (Stage 2) and the web push
service (Stage 3) are not included yet.

> This code has **not been compiled or run**. It was written without access
> to the Flutter SDK. Expect a few fixes on first run. Everything marked
> `VERIFY` needs checking against current docs.

## What's in Stage 1

- Personal space: add, edit and delete quotes (swipe left on the list to delete).
- Reminders per quote: a daily target (1 to 24 times) spread evenly between a
  first and last time. Reminders are on-device notifications (Android).
- Tapping a notification opens that quote.
- Reading flow: the Read button unlocks after 5 seconds and, for long quotes,
  only after scrolling to the end. Done is a 3-second press-and-hold.
- Streaks: daily streak (at least one read that day), per-quote streak (one read
  counts even if the target is higher), and reads against the user's own target.
- 2 streak freezes at signup, used automatically on a missed day.
- All data is stored on the device (no accounts, no backend).
- Web build runs, but **reminders do nothing on web** (they need Stage 3).

## Assumptions I made (change if wrong)

- Freezes protect **all** streaks: a frozen day neither adds to nor breaks the
  daily streak or any quote's streak.
- No tokens left means the streak resets; the best daily streak is kept.
- A "day" is the device's local calendar day.
- Reminders use inexact scheduling, so they can arrive a few minutes late (this
  avoids the exact-alarm permission).
- Notification text shows the start of the quote. Lock-screen visibility of a
  personal declaration is a privacy choice you may want to make optional later.
- Fonts (Lora, DM Sans) load through `google_fonts`, which needs internet the
  first time. Bundle them as assets if you need offline first launch.

## Setup

1. Install Flutter and confirm it works: `flutter doctor`.
2. Create a fresh project with the right name (the tests import it):

   ```
   flutter create i_decree --platforms=web,android
   ```

3. From this folder, copy over `lib/`, `test/`, `pubspec.yaml` and `.gitignore`,
   replacing the generated ones. Delete the generated `test/widget_test.dart`.
4. Run `flutter pub get`.
5. **Android setup for notifications** (VERIFY every item in the current
   flutter_local_notifications README for the version you install):
   - In `android/app/src/main/AndroidManifest.xml`, inside `<manifest>` add:

     ```xml
     <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
     <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
     ```

   - Inside `<application>` add the plugin's scheduled-notification receivers
     (`ScheduledNotificationReceiver` and `ScheduledNotificationBootReceiver`
     with its boot intent filter), exactly as in the plugin README.
   - Enable core library desugaring in the Android Gradle config, as the plugin
     README describes.
6. Run tests: `flutter test`
7. Run the app: `flutter run -d chrome` (web) or `flutter run` with an Android
   device connected.

## Test on real phones before showing anyone

Reminders are the riskiest part. On at least two Android phones, including a
cheap one with aggressive battery saving:

- [ ] Notification permission prompt appears when saving a quote with reminders on.
- [ ] A reminder fires within a few minutes of its time, with the screen off.
- [ ] Reminders still fire after the app is swiped away.
- [ ] Reminders still fire after a phone restart (and after opening the app once).
- [ ] Tapping a notification opens the right quote, both when the app is
      closed and when it's running.
- [ ] Multi-reminder quotes (e.g. hourly 6:00 to 22:00) fire at the right times.
- [ ] Reading flow: button locked at first, unlocks after the delay, long quotes
      need scrolling, 3-second hold completes, releasing early cancels.
- [ ] Streak freeze: skip a day (or change the phone date) and confirm a
      freeze is used and the streak survives.

## Project layout

```
lib/
  main.dart                     startup, notification taps, app lifecycle
  app_state.dart                data, streaks, freeze tokens, storage
  models.dart                   Quote
  theme.dart                    colours and fonts
  screens/                      home, quote list, quote view, editor
  widgets/hold_to_read_button.dart
  services/                     reminder interface + Android/web implementations
test/streak_test.dart           streak and freeze rules
```

Everything that touches the notification packages is in
`lib/services/reminder_service_mobile.dart`, so package API changes only
affect that file.

## Putting it on GitHub

1. On github.com, create a new empty repository (private is fine).
2. In the project folder:

   ```
   git init
   git add .
   git commit -m "Stage 1: personal app"
   git branch -M main
   git remote add origin <your-repo-url>
   git push -u origin main
   ```

   (VERIFY against GitHub's current quickstart.)
3. Never commit keys or config files. `.gitignore` already excludes the usual
   Firebase and signing files for Stage 3.

## Next stages

- **Stage 2:** Circles: home list of spaces, group quote lists loaded from a
  hosted JSON file (stable quote ids), copy-to-Personal.
- **Stage 3:** web push reminders via a small Firebase service.
