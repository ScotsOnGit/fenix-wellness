# Fenix Wellness Centre

The Fenix Wellness Centre mobile system: a native iOS app, the future native Android app, and a shared Supabase/Postgres backend. Staff can register, complete an induction acknowledgement, book gym sessions, check in with a QR code, access resources and wellbeing challenges, and manage their profile. Administrators manage members, bookings, hours, closures, resources, challenges, reports, and audit information.

## Handover at a glance

This repository is private and intentionally contains **no live Supabase credentials, service-role keys, user data, or production database dump**. The receiving organisation must create and own its own Supabase and mobile-store accounts before release.

| Area | Location | Status |
| --- | --- | --- |
| iOS | [`ios/`](ios) | Native SwiftUI implementation included |
| Android | [`android/`](android) | Native Kotlin/Compose auth and booking foundation included |
| Database | [`supabase/`](supabase) | Feature migrations included; baseline schema recovery required |
| Original product brief | [`docs/source-brief/`](docs/source-brief) | Reference material |

> **Release gate:** do not point either app at a new Supabase project until a complete baseline migration is restored and the entire migration sequence has passed against an empty test project. Details are in [`supabase/README.md`](supabase/README.md).

## Repository layout

```text
.
├── ios/                 SwiftUI/Xcode application and tests
├── android/             Android port location and implementation notes
├── supabase/migrations/ Versioned database feature migrations
└── docs/                Handover reference material
```

## Product rules enforced by the backend

The database, not the mobile interface, is the source of truth for these rules:

- A maximum of 20 concurrent gym users.
- Bookings begin on 15-minute boundaries and use permitted durations.
- A booking window limited to seven days, one active booking per day, and five future bookings.
- No overlapping bookings; cancellations only strictly more than one hour before the session.
- Perth facility time (`Australia/Perth`) for all displayed dates and times.
- Member access requires an administrator’s induction approval.
- Administrative actions are role-controlled and recorded in the audit trail.

## First-time setup for the receiving company

### 1. Take ownership

1. Transfer this repository to the company GitHub organisation or add its administrators as owners.
2. Create Apple Developer and Google Play Console accounts owned by the company, not an individual contractor.
3. Create a new Supabase project in a company-owned Supabase organisation.
4. Store Supabase database passwords, SMTP credentials, signing keys, and store credentials in the company password manager. Never commit them.

### 2. Provision Supabase

Follow [`supabase/README.md`](supabase/README.md) exactly. In brief: restore the missing baseline migration, link the CLI to the new project, apply the full migration history with `supabase db push`, then test the booking and RLS flows using non-admin and admin accounts.

In the Supabase Dashboard:

1. Configure email/password Auth according to the company’s onboarding policy.
2. Add the mobile redirect URIs under **Authentication → URL Configuration**. The existing iOS application uses `fenixwellness://password-reset`; change this to a company-owned unique scheme before production if the bundle identifier changes. Android must use its own unique callback URI.
3. Ensure password-recovery email templates use the redirect target passed by the app.
4. Confirm the `wellness-resources` Storage bucket remains private and that its policies work for both member and admin users.
5. Seed the initial administrator through a protected SQL/bootstrap process after the account exists. Do not use client-editable profile metadata as an authority source.

Supabase supports mobile deep-link redirect URLs, and the exact redirect URI used by an app must be on the project's allow list. See the official [redirect URL documentation](https://supabase.com/docs/guides/auth/redirect-urls) and [database-migration workflow](https://supabase.com/docs/guides/local-development/database-migrations).

### 3. Configure iOS

Requirements: a current macOS/Xcode installation, an Apple Developer team, and access to the company’s Supabase project.

1. Open [`ios/fenix.xcodeproj`](ios/fenix.xcodeproj) in Xcode.
2. Set the app’s bundle identifier, signing team, version, and build number for the company.
3. Copy `ios/fenix/SupabaseConfig.plist.example` to `ios/fenix/SupabaseConfig.plist`.
4. Set `ProjectURL` and `PublishableKey` from **Supabase Dashboard → Connect**. Add the copied plist to the app target if Xcode does not do so automatically.
5. Update `CFBundleURLTypes` in `ios/fenix/Info.plist` and the `passwordResetRedirectURL` value in `ios/fenix/AppModels.swift` together if changing the deep-link scheme. Add the exact resulting URI to Supabase Auth Redirect URLs.
6. Build on a physical device and test sign-up, sign-in, password reset, Face ID/PIN unlock, notification permission/reminder, and camera QR check-in.

`SupabaseConfig.plist` is ignored by git. It is acceptable for this file to contain the project URL and **publishable** key; it must never contain a service-role or secret key.

### 4. Implement and configure Android

See [`android/README.md`](android/README.md). The Android app is a separate native Kotlin/Compose client and consumes the same backend contract. Auth, password-reset deep linking, session persistence, booking availability, and booking confirmation are implemented. Remaining work is resources, challenges, QR check-in, local biometric/PIN unlock, notifications, and the administration experience.

Use an Android-specific deep-link callback and add an intent filter that precisely matches it. Test cold-start and warm-start password-reset callbacks on a physical device.

## Day-to-day development

- Create database changes as new Supabase migrations; do not make production-only Dashboard edits.
- Test migrations locally and against a disposable Supabase project before production.
- Keep platform configuration out of git; document new required keys in example files.
- Treat the backend RPC and RLS contract as shared API surface. Coordinate iOS and Android releases for schema-contract changes.
- Use feature branches and pull requests; require review for database migrations, authentication, and access-control changes.

## Pre-release checklist

- [ ] Complete baseline schema is committed and a fresh project can be provisioned from git alone.
- [ ] RLS policies and admin/member permissions tested with real test accounts.
- [ ] iOS and Android use the receiving company’s project URL and publishable key.
- [ ] Both mobile deep-link callback URIs are allow-listed in Supabase Auth.
- [ ] First administrator is seeded securely; ordinary users cannot self-promote.
- [ ] Storage bucket is private and PDF access is verified for authorised users only.
- [ ] Bookings at capacity, cancellation cutoff, overlapping times, time zone, check-in window, and no-shows are tested.
- [ ] Privacy policy, support contact, store metadata, signing, and crash-reporting ownership are set up by the company.

## Support and ownership

After handover, the receiving company owns the GitHub repository, Supabase organisation, Apple Developer account, Google Play Console account, signing credentials, operational monitoring, and user data. Keep at least two company administrators on each account to avoid a single-person dependency.
