# Supabase Handover

This folder contains the backend setup for the Fenix Wellbeing Facility app. It is intended for a company-owned Supabase project or a future Supabase-compatible Postgres deployment.

No live user data, bookings, storage files, database passwords, service-role keys, or production secrets are included.

## What Is Included

- `fenix_full_setup.sql`: one-shot setup SQL for a fresh Supabase project.
- `migrations/`: migration history from the delivered build.
- `functions/delete-removed-member`: Edge Function used by admins to permanently delete a member login after that member has first been marked as removed.

## Fresh Supabase Setup

1. Create a new Supabase project owned by the receiving company.
2. Enable email/password authentication.
3. Add the mobile password-reset redirect URLs in **Authentication -> URL Configuration**:
   `fenixwellness://password-reset` for iOS and `com.fenixresources.wellness://login-callback` for Android.
4. Run `fenix_full_setup.sql` in the Supabase SQL editor, or with `psql` against the new project.
5. Deploy the Edge Function:
   `supabase functions deploy delete-removed-member`
6. Set the function secrets required by `delete-removed-member`:
   `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`.
7. Create the first user account through the app sign-up screen.
8. Promote that first trusted user to admin from the SQL editor:

```sql
update public.profiles
set
    role = 'admin',
    access_status = 'active',
    induction_completed_at = now()
where lower(email) = lower('<admin-email>');
```

After the first admin exists, further admins can be managed inside the app.

## Mobile App Credentials

The mobile apps need the receiving company's Supabase project URL and publishable key.

- iOS: copy `ios/fenix/SupabaseConfig.plist.example` to `ios/fenix/SupabaseConfig.plist`, then set `ProjectURL` and `PublishableKey`.
- Android: copy `android/local.properties.example` to `android/local.properties`, then set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.

These are client-safe publishable values. Never add the service-role key to either mobile app.

## Storage

The setup SQL creates the private `wellness-resources` bucket and policies for shared PDFs and personal workout programs. Users can only see published shared resources and their own assigned personal programs. Admins can manage all uploaded resources and programs.

## Important Security Notes

- Never place the service-role key in the iOS or Android app.
- The mobile apps should only use the Supabase project URL and publishable/anon key.
- Booking limits, induction approval, member access, QR check-in, admin actions, storage access, and acknowledgement rules are enforced by database policies and RPCs, not only by the mobile interface.
- Test with separate admin and member accounts before release.

## If The Client Moves Off Hosted Supabase

This backend uses Supabase-specific pieces: Auth helper functions such as `auth.uid()`, the `auth.users` trigger, Storage tables/policies, and Edge Functions. A future AWS-hosted version should either run self-hosted Supabase on AWS or replace those pieces with equivalent AWS services and update the mobile repository layer to match.
