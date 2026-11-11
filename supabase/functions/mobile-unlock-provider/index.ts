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


function describeShape(value: any, depth = 0, path = "$", out: string[] = []): string {
  if (depth > 5 || out.length >= 45 || value == null) return out.join(" | ");
  if (Array.isArray(value)) {
    out.push(path + " = array(" + value.length + ")");
    value.slice(0, 3).forEach((item, index) => describeShape(item, depth + 1, path + "[" + index + "]", out));
    return out.join(" | ");
  }
  if (typeof value !== "object") {
    out.push(path + " = " + typeof value);
    return out.join(" | ");
  }
  const entries = Object.entries(value);
  out.push(path + " = object(" + entries.length + ")");
  for (const [key, child] of entries.slice(0, 18)) {
    if (out.length >= 45) break;
    const childPath = path + "." + key;
    if (child === null) out.push(childPath + " = null");
    else if (Array.isArray(child)) describeShape(child, depth + 1, childPath, out);
    else if (typeof child === "object") describeShape(child, depth + 1, childPath, out);
    else out.push(childPath + " = " + typeof child);
  }
  return out.join(" | ");
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

async function callProviderRestServices(apiKey: string) {
  const response = await fetch("https://mobile-unlock.com/api/v1/services", {
    method: "GET",
    headers: {
      "Authorization": "Bearer " + apiKey,
      "Accept": "application/json",
    },
  });
  const text = await response.text();
  let payload: any;
  try { payload = JSON.parse(text); }
  catch { throw new Error("REST services endpoint returned non-JSON (HTTP " + response.status + ")."); }
  if (!response.ok) {
    const message = payload?.message || payload?.error || "REST services endpoint returned HTTP " + response.status + ".";
    throw new Error(String(message).slice(0, 240));
  }
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
    const action = String(body?.action || "");
    if (!["test_connection", "sync_catalogue"].includes(action)) return json({ ok: false, error: "Unsupported action." }, 400);
    const businessId = String(body.business_id || "");
    if (!businessId) return json({ ok: false, error: "Business ID is required." }, 400);

    const { data: membership, error: membershipError } = await userClient
      .from("business_members").select("role,is_active")
      .eq("business_id", businessId).eq("user_id", authData.user.id).eq("is_active", true).maybeSingle();
    if (membershipError) throw membershipError;
    if (!membership || !["owner", "admin", "manager"].includes(String(membership.role).toLowerCase())) {
      return json({ ok: false, error: "Business owner, administrator or manager access is required." }, 403);
    }

    if (action === "test_connection") {
      const [accountPayload, servicesPayload] = await Promise.all([
        callProvider("accountinfo", providerKey), callProvider("imeiservicelist", providerKey),
      ]);
      const account = successItem(accountPayload);
      const accountData = account.AccoutInfo || account.AccountInfo || account.Account || account.LIST || account.data || account;
      const serviceItem = successItem(servicesPayload);
      const serviceData = serviceItem.LIST || serviceItem.data || serviceItem;
      const balance = accountData.credit ?? accountData.balance ?? accountData.CREDIT ?? null;
      const currency = accountData.currency ?? accountData.CURRENCY ?? null;
      return json({ ok: true, balance: balance == null ? null : String(balance), currency: currency == null ? null : String(currency),
        service_count: countServices(serviceData), checked_at: new Date().toISOString() });
    }

    const syncedAt = new Date().toISOString();
    const [accountPayload, imeiPayload, serverPayload] = await Promise.all([
      callProvider("accountinfo", providerKey), callProvider("imeiservicelist", providerKey),
      callProvider("getserverservicelist", providerKey),
    ]);
    let restPayload: any = null;
    let restError: string | null = null;
    try {
      restPayload = await callProviderRestServices(providerKey);
    } catch (error) {
      restError = String(error?.message || "REST catalogue request failed.").slice(0, 240);
    }
    const account = successItem(accountPayload);
    const accountData = account.AccoutInfo || account.AccountInfo || account.Account || account.LIST || account.data || account;
    const currency = accountData.currency ?? accountData.CURRENCY ?? null;
    const normalise = (payload: any, fallback: string) => {
      const root = successItem(payload);
      const rows: any[] = [];
      const seen = new Set<string>();
      const read = (value: any, groupName = "", groupType = fallback, inheritedKey = ""): void => {
        if (Array.isArray(value)) {
          value.forEach((entry, index) => read(entry, groupName, groupType, String(index)));
          return;
        }
        if (!value || typeof value !== "object") return;

        const v = value as Record<string, any>;
        const pick = (...keys: string[]) => {
          for (const key of keys) if (v[key] !== undefined && v[key] !== null && v[key] !== "") return v[key];
          return undefined;
        };
        const id = pick("SERVICEID", "service_id", "serviceId", "serviceid");
        const name = pick("SERVICENAME", "service_name", "serviceName", "name", "NAME");
        if (id !== undefined && name !== undefined) {
          const serviceId = String(id);
          const serviceName = String(name).trim();
          const type = String(pick("SERVICETYPE") || groupType || fallback).toUpperCase();
          const identity = type + ":" + serviceId;
          if (serviceName && !seen.has(identity)) {
            seen.add(identity);
            const credit = pick("CREDIT", "credit", "PRICE", "price");
            const numericCredit = credit == null ? null : Number(credit);
            const custom = pick("Requires.Custom", "requires_custom", "Requires", "requires");
            rows.push({
              business_id: businessId,
              provider_service_id: serviceId,
              provider_service_type: type,
              provider_group: String(groupName || pick("GROUPNAME", "group_name") || "Other"),
              service_name: serviceName,
              provider_credit: credit == null || credit === "" || !Number.isFinite(numericCredit) ? null : numericCredit,
              provider_currency: currency == null ? null : String(currency),
              delivery_time: pick("TIME", "time", "delivery_time") == null ? null : String(pick("TIME", "time", "delivery_time")),
              description: pick("INFO", "info", "description") == null ? null : String(pick("INFO", "info", "description")),
              quantity: Number.isFinite(Number(pick("QNT", "quantity"))) ? Number(pick("QNT", "quantity")) : null,
              requires_custom: Array.isArray(custom) ? custom : [],
              is_active: true,
              last_synced_at: syncedAt,
              updated_at: syncedAt,
            });
          }
          return;
        }

        const localGroup = String(pick("GROUPNAME", "group_name") || groupName || inheritedKey || "Other");
        const localType = String(pick("GROUPTYPE", "group_type") || groupType || fallback).toUpperCase();
        if (v.SERVICES && typeof v.SERVICES === "object") read(v.SERVICES, localGroup, localType);
        else if (v.services && typeof v.services === "object") read(v.services, localGroup, localType);
        else {
          for (const [key, child] of Object.entries(v)) {
            if (["MESSAGE", "message", "ACCOUNTINFO", "Account", "AccountInfo", "AccoutInfo", "apiversion"].includes(key)) continue;
            read(child, localGroup, localType, key);
          }
        }
      };

      const list = root.LIST ?? root.list ?? root.data?.LIST ?? root.data?.list ?? root.data ?? root;
      read(list, "", fallback);
      return rows;
    };
    const fusionRows = [...normalise(imeiPayload, "IMEI"), ...normalise(serverPayload, "SERVER")];
    const restRoot = restPayload?.data && typeof restPayload.data === "object" ? restPayload.data : restPayload;
    const restRows = restPayload
      ? [
          ...normalise(restRoot?.imei ?? restRoot?.IMEI ?? {}, "IMEI"),
          ...normalise(restRoot?.server ?? restRoot?.SERVER ?? {}, "SERVER"),
          ...normalise(restRoot?.remote ?? restRoot?.REMOTE ?? {}, "REMOTE"),
        ]
      : [];
    const combined = [...fusionRows, ...restRows];
    const uniqueRows = new Map<string, any>();
    for (const row of combined) {
      uniqueRows.set(row.provider_service_type + ":" + row.provider_service_id, row);
    }
    const rows = [...uniqueRows.values()];
    if (!rows.length) {
      const imeiShape = describeShape(imeiPayload);
      const serverShape = describeShape(serverPayload);
      const restShape = restPayload ? describeShape(restPayload) : "REST unavailable: " + (restError || "not returned");
      throw new Error("No services were returned by the Fusion or REST catalogues. No catalogue records were changed. IMEI: " + imeiShape + " || SERVER: " + serverShape + " || REST: " + restShape + (restError ? " || REST error: " + restError : ""));
    }
    const { error: upsertError } = await userClient.from("phone_unlocking_provider_services")
      .upsert(rows, { onConflict: "business_id,provider_service_type,provider_service_id" });
    if (upsertError) throw upsertError;
    const { error: staleError } = await userClient.from("phone_unlocking_provider_services")
      .update({ is_active: false, updated_at: syncedAt }).eq("business_id", businessId).lt("last_synced_at", syncedAt);
    if (staleError) throw staleError;
    return json({ ok: true, synced_count: rows.length,
      imei_count: rows.filter(r => r.provider_service_type === "IMEI").length,
      server_count: rows.filter(r => r.provider_service_type !== "IMEI").length,
      provider_currency: currency == null ? null : String(currency), synced_at: syncedAt,
      fusion_count: fusionRows.length, rest_count: restRows.length,
      note: "Catalogue synchronised from read-only Fusion/REST service lists. No order was submitted and no provider credit was spent." });
  } catch (error) {
    return json({ ok: false, error: error?.message || "Provider connection test failed." }, 502);
  }
});
