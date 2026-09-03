# Gym Booking App Brief (iOS + Supabase)

## Overview

This brief defines a SwiftUI iOS app for the Fenix Resources staff wellbeing facility, which can hold a maximum of 20 people at any one time. The app allows members to create an account, view availability, and book gym sessions while ensuring that no 15-minute time block ever exceeds the 20-person capacity limit.

The recommended architecture is a native SwiftUI app backed by Supabase for authentication, PostgreSQL data storage, and policy-based access control. Supabase supports Swift authentication flows and uses PostgreSQL Row Level Security (RLS), which is designed to secure database access for client applications.

## Product Goals

The app should make booking simple for members while preventing over-capacity usage and reducing unfair over-booking by a small number of users. It should also give administrators enough control to manage opening hours, blackout periods, and member bookings without requiring a custom backend in version 1.

## Core Rules

- The gym has a hard capacity of 20 people at any moment.
- Bookings start on a 15-minute boundary, such as 9:00, 9:15, 9:30, or 9:45.
- Members choose a duration of 15, 30, 45, or 60 minutes for version 1.
- A booking is valid only if every 15-minute block within the requested time range stays under the 20-person limit.
- Members can book up to 7 days in advance.
- Members can hold a maximum of 1 active booking per day.
- Members can hold a maximum of 5 future active bookings at once.
- Members can cancel their own booking up to 1 hour before the booking start time (strictly greater than 60 minutes remaining; bookings at exactly 60 minutes are past the cutoff).
- After the cancellation cutoff, cancellation requires admin action.
- Members cannot create overlapping bookings for themselves.

These fairness constraints are not built into Supabase by default, so they should be enforced in PostgreSQL functions, constraints where possible, and RLS-backed insert/update logic rather than only in the client UI.

## Registration & Access Control

Since this is a **staff benefits app for Fenix Resources employees**, registration should be restricted:

- **Domain-restricted sign-up**: Only email addresses ending in `@fenix.com.au` (or other approved company domains) may register.
- This restriction should be enforced server-side via the PostgreSQL `can_register()` function or a Supabase Auth hook — not only in the client.
- Alternatively, an **invite-code model** may be used where HR distributes single-use codes to eligible staff.
- The first admin account should be **seeded via SQL migration** during initial deployment, not created through the app's sign-up flow.

## Recommended Stack

| Layer | Choice | Reason |
|------|--------|--------|
| iOS app | SwiftUI (iOS 17+) | Native Apple UI framework with clean support for modern app architecture. |
| State management | @Observable / Observation framework | Lightweight, modern, removes need for third-party state libraries. |
| Concurrency | Swift Concurrency (async/await) | All Supabase calls should use structured concurrency for clarity and cancellation support. |
| Backend platform | Supabase | Provides auth, PostgreSQL, APIs, real-time features, and Swift SDK without a custom backend. |
| Real-time | Supabase Realtime | Channel subscriptions on the availability view to reflect live changes when other users book/cancel. |
| Database | PostgreSQL | Strong support for transactional logic, indexing, functions, and policy-based access control. |
| Auth | Email and password (domain-restricted) | Simple for members and supported directly by Supabase Swift. |
| Authorization | Row Level Security | Supabase recommends RLS to control which rows each user can access. |

### Architecture Pattern

The app should implement a thin **repository layer** between SwiftUI views and the Supabase client. This provides:

- Clean separation of concerns
- Ability to mock data sources for SwiftUI Previews
- Testability against a staging Supabase project without touching production

## Data Model

### Tables

#### `profiles`

Stores member profile information linked to Supabase Auth.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | References `auth.users.id` |
| full_name | TEXT | Required |
| email | TEXT | Optional mirror of auth email if needed for display |
| phone | TEXT | Optional |
| role | TEXT | `member` or `admin` |
| created_at | TIMESTAMPTZ | Default current timestamp |

#### `bookings`

Stores one row per gym session.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | Default generated UUID |
| user_id | UUID FK | References `profiles.id` |
| start_time | TIMESTAMPTZ | Must be on a 15-minute boundary |
| end_time | TIMESTAMPTZ | Must be after `start_time` |
| cancelled_at | TIMESTAMPTZ | Null unless cancelled |
| created_at | TIMESTAMPTZ | Default current timestamp |

### Key Constraints

- `end_time > start_time`
- Duration must be one of: 15, 30, 45, or 60 minutes
- No overlapping active bookings for the same user
- No booking may start earlier than current time
- No booking may start more than 7 days ahead

### Supporting Data

#### `facility_rules`

Stores values such as maximum capacity, cancellation cutoff, maximum future bookings, and booking horizon. This keeps hard-coded business rules out of the app binary and makes later policy changes easier.

**Caching strategy**: The app should fetch `facility_rules` on each app launch and when returning to the foreground. Rules should never be cached beyond a single session. If the rules fetch fails (e.g., no connectivity), the app should display a "cannot confirm current availability" state and prevent booking attempts until rules are refreshed.

#### `opening_hours` and `blackout_periods`

These tables let administrators define when the gym can be booked and when it cannot, such as holidays, maintenance closures, or special events.

## Capacity Logic

Capacity must be enforced in the database, not just in SwiftUI. The booking insert path should rely on a PostgreSQL function that validates the request before the row is allowed.

### Validation Requirements

When a member attempts to book:

1. Confirm the start time is aligned to a 15-minute boundary.
2. Confirm the duration is allowed.
3. Confirm the booking is within opening hours.
4. Confirm the booking is inside the 7-day booking horizon.
5. Confirm the user has not exceeded active booking limits.
6. Confirm the user has no overlapping active booking.
7. Check every 15-minute block within the requested interval.
8. Reject the request if any block would exceed 20 active users.

### Suggested Database Approach

Implement a PostgreSQL function such as `can_book_session(start_time, end_time, user_id)` that returns either success or a failure reason. The booking insert should only succeed when that function returns allowed, and the RLS insert policy should rely on the same logic so a modified client cannot bypass the rules.

**Race condition handling**: PostgreSQL's row-level locking within the RPC will serialise simultaneous booking attempts. When two users attempt to book the last available place at the same moment, the first transaction to acquire the lock wins; the second will fail validation and receive a clear "slot no longer available" response. The `SELECT` within `can_book_session` should use `FOR UPDATE` or an advisory lock to guarantee serialisation.

A companion RPC or SQL view such as `get_availability_for_date(date)` should return all 15-minute start times with remaining capacity information for the selected day. That keeps the SwiftUI booking screen fast and avoids re-implementing booking logic in the client.

## Real-Time Updates

The availability screen should subscribe to a **Supabase Realtime channel** on the `bookings` table (filtered to the currently displayed date). When another user creates or cancels a booking:

- The availability grid should update automatically without requiring a manual refresh.
- If a slot the user is currently viewing becomes full, the UI should disable it immediately with a brief visual transition.
- If a slot opens up, it should appear as available.

This is important because with a 20-person cap and potentially dozens of Fenix staff using the app, simultaneous booking attempts are likely during peak hours (e.g., before/after work, lunch).

## Timezone Handling

All timestamps stored in Supabase must be UTC. However, all **display** in the app must be pinned to `Australia/Perth` (AWST, UTC+8) regardless of the device's current locale or timezone setting.

Western Australia does not observe daylight saving time, which simplifies this. However, if a Fenix staff member is travelling interstate or internationally, the app must still show Perth facility time — not their device's local time.

Implementation:
- Use a hardcoded `TimeZone(identifier: "Australia/Perth")` for all date formatting in the UI.
- The `facility_rules` table should store the facility timezone identifier so this can be changed without an app update if Fenix ever opens facilities elsewhere.

## Authentication and Authorization

Members will create accounts in-app using email and password. Supabase Swift supports sign-up directly, but the implementation should decide early whether email confirmation is required, because confirmation settings affect whether a session is returned immediately after signup.

**Recommendation for v1**: Skip email confirmation. Since this is a staff app with domain-restricted registration, the risk of fake accounts is minimal. This reduces friction for onboarding. If confirmation is desired later, it can be enabled without schema changes.

Authorization should not rely on user-editable metadata for admin privileges. Administrator role checks should live in protected profile data and RLS policies, not in client-controlled fields.

### Minimum RLS Rules

- Members can read their own profile.
- Members can update their own basic profile details (not `role`).
- Members can read their own active and historical bookings.
- Members can create their own bookings only when validation passes.
- Members can cancel their own booking before the cutoff (strictly > 60 minutes before start time).
- Admins can read all bookings and manage cancellations.
- Admins can manage operating hours, blackout periods, and rules.

## iOS App Structure

Apple's Human Interface Guidelines emphasise clarity and simple task-focused flows, which fits a lightweight booking app better than a complex dashboard-style interface.

### Main Screens

#### 1. Welcome / Login
- Email
- Password
- Sign in button
- Link to create account
- Forgot password link

#### 2. Register
- Full name
- Email (validated to `@fenix.com.au` domain client-side, enforced server-side)
- Password
- Optional phone number
- Create account button

#### 3. Book
- Date picker limited to today through 7 days ahead
- Available 15-minute start times for the selected date (live-updating via Realtime)
- Duration picker: 15, 30, 45, 60 minutes
- Visual status for each start time: available, nearly full, full
- Clear explanation when a chosen duration crosses into a full period

#### 4. Booking Confirmation
- Date
- Start time
- End time
- Duration
- Booking policy summary
- Confirm action

#### 5. My Bookings
- Upcoming bookings
- Past bookings
- Cancellation option when still inside allowed window
- Status labels such as active, cancelled, or completed

#### 6. Profile
- Name
- Email
- Optional phone number
- Log out

#### 7. Admin Panel
- Today's bookings
- Filter by date
- Cancel a booking
- Manage opening hours
- Manage blackout periods
- View booking statistics (phase 2)

## UX Notes

The booking flow should be short and obvious:

1. Select date.
2. Select start time.
3. Select duration.
4. Review whether the full requested interval has capacity.
5. Confirm booking.

The app should explain failures precisely. Instead of a generic error, messages should say things like "This 45-minute session crosses a full block at 9:30" or "You already have a booking on this day." Clear, direct messaging will reduce support friction and make the system feel fairer.

### Connectivity & Optimistic UI

- The app should use an **optimistic UI pattern**: show a "booking confirmed" state immediately on tap, then confirm with the server.
- If the server rejects the booking (race condition, lost connectivity), transition to a clear **"Booking not confirmed"** state with the specific reason and a retry option.
- If connectivity is lost during confirmation, the app should retry once when connectivity resumes, then show an "Unable to confirm — please check My Bookings" message.

The visual design should remain simple and native. Version 1 should avoid over-designed admin dashboards or crowded status displays.

## Availability Model

The app should not present "slots" as fixed standalone objects if members can book variable session lengths. Instead, it should present start times plus a chosen duration, with server-calculated availability for the whole requested range.

Example:

- Start time: 09:00
- Duration: 45 minutes
- Occupied blocks checked: 09:00–09:15, 09:15–09:30, 09:30–09:45

A start time may look available for 15 minutes but not for 45 minutes. The API or RPC layer should make this explicit so the UI can disable impossible combinations before submission where practical, while still treating the database as the final authority.

## Colour Palette & Visual Identity

Since this is a Fenix Resources staff app, the visual design should align with corporate branding:

| Colour | Hex | Usage |
|--------|-----|-------|
| Fenix Navy | `#1A1A2E` | Navigation bars, headers, primary text |
| Fenix Gold | `#D4842A` | Primary accent, CTA buttons, active states, brand mark |
| White | `#FFFFFF` | Cards, content backgrounds, body text on dark |
| Light Grey | `#F4F4F4` | Section backgrounds, availability grid base |
| Available Green | SF Symbol `systemGreen` | Available slots indicator |
| Nearly Full Amber | SF Symbol `systemOrange` | 15–19 occupants indicator |
| Full Red | SF Symbol `systemRed` | At-capacity / unavailable indicator |

The app should feel **clean, corporate, and native iOS** — not over-branded. Use the Fenix Gold sparingly for primary actions and the navy for structure. Lean on Apple system colours for status indicators to maintain accessibility and platform consistency.

Typography should use the system San Francisco font throughout, with no custom typefaces in v1.

## Suggested API / Supabase Surface

The app can use Supabase Auth plus either direct table access with RLS or RPCs for business-critical operations.

### Recommended operations

- Sign up member account (domain-validated).
- Sign in member account.
- Fetch profile.
- Fetch availability for a chosen date.
- Create booking through an RPC or validated insert path.
- Fetch current user bookings.
- Cancel booking.
- Subscribe to Realtime channel for availability changes.
- Fetch admin booking list.
- Update operating hours or blackout periods.

For critical booking operations, RPCs are preferable to raw inserts because they centralise validation and produce clearer structured error responses.

## Implementation Plan

| Phase | Scope | Estimate |
|------|-------|----------|
| 1 | Supabase project, schema, auth, RLS, booking validation functions, admin seed | 1.5–2 days |
| 2 | SwiftUI app scaffold, repository layer, auth flow, session handling | 1–1.5 days |
| 3 | Booking UI, availability display, Realtime subscription, booking confirmation | 2–2.5 days |
| 4 | My Bookings, cancellation flow, profile screen | 1 day |
| 5 | Admin tools for bookings, hours, blackout periods | 1–2 days |
| 6 | Testing (unit + integration against staging), timezone handling, edge cases, polish | 1.5–2.5 days |
| 7 | TestFlight deployment | 0.5 day |

A realistic first version is around **8.5 to 12 focused development days**, depending on polish level, testing depth, and whether admin controls are included in the initial release.

## Testing Strategy

Given the race-condition-sensitive nature of a capacity-limited booking system, testing should not be deferred:

- **Unit tests**: Repository layer logic, date/timezone formatting, validation helpers.
- **Integration tests**: Run against a dedicated Supabase staging project. Test concurrent booking scenarios by calling the RPC from multiple async tasks simultaneously.
- **UI tests**: Critical path — login → book → confirm → appears in My Bookings → cancel.
- **Edge case tests**: Booking at exact capacity, cancellation at boundary, expired session handling.

## Edge Cases

The brief should explicitly account for these scenarios:

- Two users attempt to book the last available place at the same moment → **PostgreSQL row-level locking serialises; first-in wins, second receives "slot no longer available"**
- A user loses connectivity during booking confirmation → **Optimistic UI with retry and "unable to confirm" fallback state**
- The device timezone differs from the facility timezone → **All display pinned to Australia/Perth regardless of device locale**
- A booking spans closing time → **Rejected by `can_book_session` validation against `opening_hours`**
- A booking sits exactly at the cancellation cutoff → **Strictly > 60 minutes; at exactly 60 minutes, cancellation is denied**
- An admin changes operating hours after members already booked → **Existing bookings are grandfathered; admin can manually cancel affected bookings with notification**
- A user signs up but does not complete email confirmation, if confirmation is enabled → **Recommendation: skip confirmation in v1 for staff app**

## Phase 2 Options

These features are useful but should not block version 1:

- Waitlist for full periods (notify when a space opens)
- Push notifications via APNs when a cancellation creates availability
- Usage analytics and peak period reporting for admin
- QR check-in at facility entry
- Health declarations or attendance notes
- Recurring personal routines (if fairness rules still allow)
- Multi-facility support (if Fenix adds additional wellbeing facilities)

## Final Recommendation

The strongest version of this app is a native SwiftUI client with Supabase-backed authentication and PostgreSQL-enforced booking rules. The product should be domain-restricted to Fenix Resources staff, use real-time updates for availability, pin all times to the facility timezone, and enforce all business rules at the database level.

That approach keeps the version 1 product simple, secure, and realistic to build while leaving enough room for later enhancements such as waitlists, notifications, and richer analytics.
