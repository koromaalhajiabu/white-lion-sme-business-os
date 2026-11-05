import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return Response.json({ error: "POST required" }, { status: 405, headers: cors });
  try {
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!token) return Response.json({ error: "Authentication required" }, { status: 401, headers: cors });
    const url = Deno.env.get("SUPABASE_URL")!;
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return Response.json({ error: "Invalid session" }, { status: 401, headers: cors });
    const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false }
    });
    const { data: developer, error: developerError } = await caller.rpc("is_platform_developer");
    if (developerError || developer !== true) return Response.json({ error: "Developer access required" }, { status: 403, headers: cors });

    const body = await req.json();
    const id = String(body.request_id || "");
    const { data: request, error: requestError } = await admin.from("platform_account_deletion_requests")
      .select("id,target_user_id,target_email,scheduled_for,status").eq("id", id).single();
    if (requestError || !request) return Response.json({ error: "Request not found" }, { status: 404, headers: cors });
    if (request.status !== "pending" || Date.parse(request.scheduled_for) > Date.now())
      return Response.json({ error: "Request is not yet eligible" }, { status: 409, headers: cors });

    const { data: targetData, error: targetError } = await admin.auth.admin.getUserById(request.target_user_id);
    if (targetError || !targetData.user) return Response.json({ error: "Target account not found" }, { status: 404, headers: cors });
    if (targetData.user.email?.toLowerCase() !== request.target_email.toLowerCase())
      return Response.json({ error: "Target email changed; manual review required" }, { status: 409, headers: cors });
    if (targetData.user.id === authData.user.id) return Response.json({ error: "Self-deletion prohibited" }, { status: 403, headers: cors });

    const { data: allowlist, error: allowError } = await admin.from("platform_developer_emails").select("email");
    if (allowError) throw allowError;
    if ((allowlist || []).some(x => x.email.toLowerCase() === request.target_email.toLowerCase()))
      return Response.json({ error: "Developer accounts are protected" }, { status: 403, headers: cors });

    const { count, error: ownerError } = await admin.from("businesses").select("id", { count: "exact", head: true })
      .eq("owner_user_id", request.target_user_id);
    if (ownerError) throw ownerError;
    if ((count || 0) > 0) return Response.json({ error: "Transfer business ownership first" }, { status: 409, headers: cors });

    const { error: deleteError } = await admin.auth.admin.deleteUser(request.target_user_id);
    if (deleteError) throw deleteError;
    const { error: finishError } = await admin.from("platform_account_deletion_requests")
      .update({ status: "completed", completed_at: new Date().toISOString() })
      .eq("id", id).eq("status", "pending");
    if (finishError) throw finishError;
    await admin.from("platform_audit_logs").insert({
      actor_user_id: authData.user.id, actor_email_snapshot: authData.user.email || null,
      action: "account_permanently_deleted", entity_table: "auth.users", entity_id: request.target_user_id,
      details: { request_id: id, target_email: request.target_email }
    });
    return Response.json({ ok: true, message: "Account permanently deleted after the 30-day recovery period." }, { headers: cors });
  } catch (e) {
    return Response.json({ error: e?.message || "Processing failed" }, { status: 500, headers: cors });
  }
});
