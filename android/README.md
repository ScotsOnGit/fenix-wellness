# Android app

The Android client has not yet been implemented. This directory is its permanent home in the handover repository so that iOS, Android, and the shared Supabase schema stay versioned together.

## Recommended implementation

- Kotlin and Jetpack Compose
- A repository layer matching `ios/fenix/GymBookingRepository.swift`
- Supabase Kotlin for Auth, PostgREST/RPC, Storage, and Realtime
- Android Keystore plus `BiometricPrompt` for local unlock
- CameraX plus ML Kit for QR check-in
- WorkManager and notification channels for booking reminders

## Non-negotiable compatibility requirements

The Android app must use the same Supabase project, database RPCs, RLS policies, storage bucket, booking rules, and `Australia/Perth` facility timezone as iOS. It must not duplicate capacity or booking-authorisation logic on-device.

Configure Android password-recovery deep linking with a unique app URI, for example `com.fenixresources.wellness://login-callback`, add that URI to Supabase Auth Redirect URLs, declare a matching Android intent filter, and pass the URI when requesting a password reset.

See the root README and `../supabase/README.md` before starting implementation.
