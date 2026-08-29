import "@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  })
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405)
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse({ error: "Server configuration is incomplete." }, 500)
  }

  const authHeader = req.headers.get("Authorization") ?? ""
  if (!authHeader.startsWith("Bearer ")) {
    return jsonResponse({ error: "Sign in as an admin to delete a removed member login." }, 401)
  }

  const body = await req.json().catch(() => ({})) as Record<string, unknown>
  const rawUserID = body.user_id ?? body.userID
  const userID = typeof rawUserID === "string" ? rawUserID.trim() : ""

  if (!uuidPattern.test(userID)) {
    return jsonResponse({ error: "Choose a valid member account to delete." }, 400)
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: authData, error: authError } = await userClient.auth.getUser()
  const actor = authData.user
  if (authError || !actor) {
    return jsonResponse({ error: "Your admin session has expired. Sign in again and retry." }, 401)
  }

  if (actor.id === userID) {
    return jsonResponse({ error: "You cannot delete your own login account." }, 400)
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: actorProfile, error: actorProfileError } = await adminClient
    .from("profiles")
    .select("id, role")
    .eq("id", actor.id)
    .maybeSingle()

  if (actorProfileError) {
    return jsonResponse({ error: actorProfileError.message }, 500)
  }

  if (actorProfile?.role !== "admin") {
    return jsonResponse({ error: "Only admins can delete removed member logins." }, 403)
  }

  const { data: targetProfile, error: targetProfileError } = await adminClient
    .from("profiles")
    .select("id, full_name, email, role, access_status, induction_completed_at, induction_completed_by")
    .eq("id", userID)
    .maybeSingle()

  if (targetProfileError) {
    return jsonResponse({ error: targetProfileError.message }, 500)
  }

  if (!targetProfile) {
    return jsonResponse({ error: "That member account was not found." }, 404)
  }

  if (targetProfile.role !== "member") {
    return jsonResponse({ error: "Admin accounts cannot be deleted from this screen." }, 400)
  }

  if (targetProfile.access_status !== "removed") {
    return jsonResponse({ error: "Remove this member's access before deleting their login account." }, 400)
  }

  const now = new Date().toISOString()
  const { data: cancelledBookings, error: bookingsError } = await adminClient
    .from("bookings")
    .update({ cancelled_at: now })
    .eq("user_id", userID)
    .is("cancelled_at", null)
    .gt("start_time", now)
    .select("id")

  if (bookingsError) {
    return jsonResponse({ error: bookingsError.message }, 500)
  }

  const { data: archivedPrograms, error: programsError } = await adminClient
    .from("program_assignments")
    .update({ archived_at: now })
    .eq("user_id", userID)
    .is("archived_at", null)
    .select("id")

  if (programsError) {
    return jsonResponse({ error: programsError.message }, 500)
  }

  const { error: deleteError } = await adminClient.auth.admin.deleteUser(userID, false)
  if (deleteError) {
    return jsonResponse({ error: deleteError.message }, 500)
  }

  const redactedEmail = `deleted-${userID}@deleted.local`
  const { error: redactProfileError } = await adminClient
    .from("profiles")
    .update({
      full_name: "Deleted member",
      email: redactedEmail,
      phone: "",
      access_status: "removed",
      induction_completed_at: null,
      induction_completed_by: null,
    })
    .eq("id", userID)

  if (redactProfileError) {
    return jsonResponse({ error: redactProfileError.message }, 500)
  }

  await adminClient
    .from("audit_log")
    .insert({
      actor_id: actor.id,
      action: "member_auth_deleted",
      target_type: "profile",
      target_id: userID,
      before_data: targetProfile,
      after_data: {
        future_bookings_cancelled: cancelledBookings?.length ?? 0,
        program_assignments_archived: archivedPrograms?.length ?? 0,
        profile_email_redacted_to: redactedEmail,
      },
    })

  return jsonResponse({
    deleted: true,
    user_id: userID,
    email: targetProfile.email,
    future_bookings_cancelled: cancelledBookings?.length ?? 0,
    program_assignments_archived: archivedPrograms?.length ?? 0,
  })
})
