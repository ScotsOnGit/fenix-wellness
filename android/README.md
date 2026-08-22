# Android app

The native Android client is implemented to the first delivery milestone: email/password registration and sign-in, secure local session storage using Android Keystore, password-reset deep linking, live booking availability, and booking confirmation. It uses the same Supabase REST/RPC contract as iOS, so all access and capacity decisions remain server-side.

## Run it

1. Install Android Studio with Android SDK Platform 35 and JDK 17.
2. Copy `local.properties.example` to `local.properties` and set the receiving company's Supabase URL and publishable key.
3. Open this `android/` directory in Android Studio, then sync and run the `app` configuration.
4. In Supabase Auth URL Configuration, add `com.fenixresources.wellness://login-callback` as an allowed redirect URL. Change this URI in both `AndroidManifest.xml` and `SupabaseApi.kt` if the company changes the application ID.

The publishable key may be present in a mobile app; the service-role/secret key must never be placed in `local.properties`, GitHub, or a mobile binary.

## Included features

- Session restore and sign-out
- Email/password sign-in and registration
- Password-reset email and cold/warm deep-link callback handling
- Keystore-encrypted token storage
- Perth-date booking availability through `get_availability_for_date`
- Booking creation through `create_booking`

## Next features

- Resources and private PDF access
- Wellbeing challenges
- CameraX/ML Kit QR check-in and check-out
- Biometric/PIN local unlock
- Local notifications and the administration experience

The Android app must use the same Supabase project, database RPCs, RLS policies, storage bucket, booking rules, and `Australia/Perth` facility timezone as iOS. It must not duplicate capacity or booking-authorisation logic on-device.

See the root README and `../supabase/README.md` before release.
