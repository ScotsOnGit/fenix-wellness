# Supabase handover

This directory is the source-controlled database migration history for the Fenix Wellness Centre application. It must be applied to the receiving organisation's own Supabase project; neither mobile app should be pointed at the development project used during delivery.

## Important migration-history limitation

The supplied history begins with feature-layer migrations that alter the original booking schema (`profiles`, `bookings`, `facility_rules`, `opening_hours`, `blackout_periods`, and supporting RPCs). The original baseline migration was not present in the source workspace. Therefore these migrations cannot, by themselves, initialise an empty Supabase project.

Before go-live, obtain and commit a baseline schema migration from the previous project owner (preferably a `supabase db pull` export that includes the public, storage, and relevant auth-trigger definitions). Test the complete migration chain against a new empty project before distributing either app. Do not improvise or apply the feature migrations manually in the Dashboard.

## Receiving-company setup

1. Create a new Supabase project in an organisation owned by the receiving company.
2. Install a current Supabase CLI, authenticate with `supabase login`, then initialise/link this directory: `supabase init` (only if `config.toml` is absent) and `supabase link --project-ref <project-ref>`.
3. Add the recovered baseline migration before the existing migrations, preserving chronological filenames.
4. Run `supabase db push` against the new project.
5. Review every migration in the Dashboard SQL editor or with `supabase migration list`; then verify tables, RPCs, RLS policies, and the private `wellness-resources` bucket.
6. Configure Auth URL settings and the mobile deep links described in the root README.
7. Create the first administrator using a controlled SQL/bootstrap process. Do not grant admin role from a mobile client.
8. Copy the new project's URL and publishable key to each platform's untracked local configuration file.

## Security rules

- Keep the Supabase service-role/secret key out of mobile applications, git history, screenshots, and CI logs.
- A publishable/anon key belongs in the apps and is protected by RLS; it is not a server secret.
- RLS and database RPCs, not UI checks, enforce booking capacity, cancellation, access approval, and administration.
- Review generated SQL and RLS policies before production use. The migrations use privileged functions and storage policies, so a migration test on a blank project is mandatory.
