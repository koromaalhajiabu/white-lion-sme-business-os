import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "https://koromaalhajiabu.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function providerError(payload: any): string | null {
  const item = payload?.ERROR?.[0] || payload?.error;
  return item ? String(item.MESSAGE || item.message || "Provider returned an error.") : null;
}

function successItem(payload: any): any {
  return payload?.SUCCESS?.[0] || payload?.data?.[0] || payload?.data || payload || {};
}

function countServices(value: any): number {
  if (Array.isArray(value)) return value.reduce((n, item) => n + countServices(item), 0);
  if (!value || typeof value !== "object") return 0;
  if (value.SERVICEID != null || value.service_id != null) return 1;
  return Object.values(value).reduce((n, item) => n + countServices(item), 0);
}

async function callProvider(action: string, apiKey: string) {
  const body = new URLSearchParams({ action, apikey: apiKey });
  const response = await fetch("https://mobile-unlock.com/api/fusion", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json" },
    body,
  });
  const text = await response.text();
  let payload: any;
  try { payload = JSON.parse(text); }
  catch { throw new Error("Provider returned a non-JSON response (HTTP " + response.status + ")."); }
  if (!response.ok) throw new Error("Provider HTTP error " + response.status + ".");
  const problem = providerError(payload);
  if (problem) throw new Error(problem);
  return payload;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "POST required." }, 405);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) return json({ ok: false, error: "Sign in is required." }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const providerKey = Deno.env.get("MOBILE_UNLOCK_API_KEY");
    if (!supabaseUrl || !anonKey || !providerKey) {
      return json({ ok: false, error: "Server configuration is incomplete. Check Supabase function secrets." }, 500);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: "Bearer " + token } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser(token);
    if (authError || !authData.user) return json({ ok: false, error: "Your session is invalid. Sign in again." }, 401);

    const body = await req.json();
    if (body?.action !== "test_connection") return json({ ok: false, error: "Unsupported action." }, 400);
    const businessId = String(body.business_id || "");
    if (!businessId) return json({ ok: false, error: "Business ID is required." }, 400);

    const { data: membership, error: membershipError } = await userClient
      .from("business_members")
      .select("role,is_active")
      .eq("business_id", businessId)
      .eq("user_id", authData.user.id)
      .eq("is_active", true)
      .maybeSingle();
    if (membershipError) throw membershipError;
    if (!membership || !["owner", "admin", "manager"].includes(String(membership.role).toLowerCase())) {
      return json({ ok: false, error: "Business owner, administrator or manager access is required." }, 403);
    }

    const [accountPayload, servicesPayload] = await Promise.all([
      callProvider("accountinfo", providerKey),
      callProvider("imeiservicelist", providerKey),
    ]);
    const account = successItem(accountPayload);
    const accountData = account.Account || account.LIST || account.data || account;
    const serviceItem = successItem(servicesPayload);
    const serviceData = serviceItem.LIST || serviceItem.data || serviceItem;
    const balance = accountData.credit ?? accountData.balance ?? accountData.CREDIT ?? null;
    const currency = accountData.currency ?? accountData.CURRENCY ?? null;

    return json({
      ok: true,
      balance: balance == null ? null : String(balance),
      currency: currency == null ? null : String(currency),
      service_count: countServices(serviceData),
      checked_at: new Date().toISOString(),
    });
  } catch (error) {
    return json({ ok: false, error: error?.message || "Provider connection test failed." }, 502);
  }
});
