# Android App

The native Android client is implemented to the first delivery milestone: email/password registration and sign-in, secure local session storage using Android Keystore, password-reset deep linking, live booking availability, and booking confirmation. It uses the same Supabase REST/RPC contract as iOS, so all access and capacity decisions remain server-side.

Android is not yet at full feature parity with the iOS app. Treat it as a maintained foundation for a later Android release, not as the primary production client.

## Run it

1. Install Android Studio with Android SDK Platform 35 and JDK 17.
2. The app defaults to the current development Supabase project. To use a different project, copy `local.properties.example` to `local.properties` and set the receiving company's Supabase URL and publishable key.
3. Open this `android/` directory in Android Studio, then sync and run the `app` configuration.
4. In Supabase Auth URL Configuration, add `com.fenixresources.wellness://login-callback` as an allowed redirect URL. Change this URI in both `AndroidManifest.xml` and `SupabaseApi.kt` if the company changes the application ID.

The publishable key may be present in a mobile app; the service-role/secret key must never be placed in `local.properties`, GitHub, or a mobile binary.

## Where Credentials Are Set

- `android/app/build.gradle.kts`: contains the current development Supabase project URL and publishable key as defaults.
- `android/local.properties`: optional receiving-company Supabase override values go here. This file is ignored by git.
- `android/local.properties.example`: current development values committed for handover and as an override template.
- `android/app/src/main/java/com/fenixresources/wellness/data/SupabaseApi.kt`: uses those values through `BuildConfig`.

## Included features

- Session restore and sign-out
- Email/password sign-in and registration
- Password-reset email and cold/warm deep-link callback handling
- Keystore-encrypted token storage
- Perth-date booking availability through `get_availability_for_date`
- Booking creation through `create_booking`
- Personal-email registration wording
- Password confirmation and password visibility toggles

## Required For Android Feature Parity

- Resources and private PDF access
- Wellbeing challenges
- CameraX/ML Kit QR check-in and check-out
- Biometric/PIN local unlock
- Local notifications
- Member booking list, cancellation, and attendance states
- Admin operations, member management, reporting, access management, acknowledgement editing, resources, programs, challenges, and audit log screens

The Android app must use the same Supabase project, database RPCs, RLS policies, storage bucket, booking rules, and `Australia/Perth` facility timezone as iOS. It must not duplicate capacity or booking-authorisation logic on-device.

See the root README and `../supabase/README.md` before release.
