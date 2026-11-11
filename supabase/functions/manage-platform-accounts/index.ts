import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DEVELOPER_EMAIL = "koromaalhajiabu0@gmail.com";
const ALLOWED_ROLES = new Set(["admin", "manager", "accountant", "storekeeper", "cashier", "viewer"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return Response.json({ error: "POST required" }, { status: 405, headers: cors });

  try {
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\\s+/i, "");
    if (!token) return Response.json({ error: "Authentication required" }, { status: 401, headers: cors });

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return Response.json({ error: "Invalid session" }, { status: 401, headers: cors });
    if (authData.user.email?.toLowerCase() !== DEVELOPER_EMAIL) {
      return Response.json({ error: "Developer access required" }, { status: 403, headers: cors });
    }

    const body = await req.json();
    const action = String(body.action || "");
    const actorId = authData.user.id;
    const actorEmail = authData.user.email || DEVELOPER_EMAIL;

    const audit = async (event: string, entityId: string, details: Record<string, unknown>) => {
      const { error } = await admin.from("platform_audit_logs").insert({
        actor_user_id: actorId,
        actor_email_snapshot: actorEmail,
        action: event,
        entity_table: "auth.users",
        entity_id: entityId,
        details
      });
      if (error) throw error;
    };

    if (action === "invite") {
      const email = String(body.email || "").trim().toLowerCase();
      const fullName = String(body.full_name || "").trim();
      const businessId = String(body.business_id || "");
      const role = String(body.role || "admin");
      if (!/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(email) || !fullName || !businessId || !ALLOWED_ROLES.has(role)) {
        return Response.json({ error: "Provide a valid email, full name, business workspace and permitted role." }, { status: 400, headers: cors });
      }
      if (email === DEVELOPER_EMAIL) return Response.json({ error: "The developer account cannot be invited or replaced." }, { status: 403, headers: cors });

      const { data: business, error: businessError } = await admin.from("businesses").select("id,name").eq("id", businessId).maybeSingle();
      if (businessError) throw businessError;
      if (!business) return Response.json({ error: "Selected business workspace was not found." }, { status: 404, headers: cors });

      const { data: invitation, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
        data: { full_name: fullName }
      });
      if (inviteError) throw inviteError;
      if (!invitation.user) throw new Error("Supabase did not return the invited account.");

      const { error: memberError } = await admin.from("business_members").upsert({
        business_id: businessId,
        user_id: invitation.user.id,
        role,
        is_active: true,
        invited_by: actorId
      }, { onConflict: "business_id,user_id" });
      if (memberError) throw memberError;

      await audit("platform_account_invited", invitation.user.id, {
        email, full_name: fullName, business_id: businessId, business_name: business.name, role
      });
      return Response.json({
        ok: true,
        message: "Invitation sent to " + email + ". " + role.toUpperCase() + " access was assigned to " + business.name + "."
      }, { headers: cors });
    }

    if (action === "update_profile") {
      const userId = String(body.user_id || "");
      const fullName = String(body.full_name || "").trim();
      const email = String(body.email || "").trim().toLowerCase();
      if (!userId || !fullName || !/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(email)) {
        return Response.json({ error: "Provide the account ID, full name and a valid email address." }, { status: 400, headers: cors });
      }
      if (userId === actorId || email === DEVELOPER_EMAIL) {
        return Response.json({ error: "The private developer account is protected." }, { status: 403, headers: cors });
      }
      const { data: targetData, error: targetError } = await admin.auth.admin.getUserById(userId);
      if (targetError || !targetData.user) return Response.json({ error: "Account not found." }, { status: 404, headers: cors });
      const oldEmail = (targetData.user.email || "").toLowerCase();
      if (oldEmail === DEVELOPER_EMAIL) return Response.json({ error: "The private developer account is protected." }, { status: 403, headers: cors });

      const { data: protectedEmail, error: protectedError } = await admin.from("platform_developer_emails").select("email").eq("email", email).maybeSingle();
      if (protectedError) throw protectedError;
      if (protectedEmail) return Response.json({ error: "That email is reserved for a protected developer account." }, { status: 409, headers: cors });

      const { error: profileError } = await admin.from("profiles").update({ full_name: fullName }).eq("id", userId);
      if (profileError) throw profileError;
      const metadata = { ...(targetData.user.user_metadata || {}), full_name: fullName };
      const attributes: Record<string, unknown> = { user_metadata: metadata };
      if (email !== oldEmail) attributes.email = email;
      const { data: updated, error: updateError } = await admin.auth.admin.updateUserById(userId, attributes);
      if (updateError) throw updateError;

      await audit("platform_account_profile_updated", userId, {
        previous_email: oldEmail, email, full_name: fullName,
        email_change_pending_confirmation: email !== oldEmail
      });
      return Response.json({
        ok: true,
        message: email !== oldEmail
          ? "Profile updated. Supabase has sent an email confirmation to the new address; the change takes effect after confirmation."
          : "Account name updated successfully."
      }, { headers: cors });
    }

    return Response.json({ error: "Unsupported account-management action." }, { status: 400, headers: cors });
  } catch (error) {
    return Response.json({ error: error?.message || "Account management failed." }, { status: 500, headers: cors });
  }
});
