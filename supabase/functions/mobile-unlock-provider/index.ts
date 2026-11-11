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

async function callProviderAtHost(host: string, action: string, apiKey: string) {
  const body = new URLSearchParams({ action, apikey: apiKey });
  const response = await fetch(host + "/api/fusion", {
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

// Account verification continues using the already-confirmed apex host.
// Catalogue requests also try the documented www host because the provider
// may route its reseller catalogue differently between the two hostnames.
async function callProvider(action: string, apiKey: string) {
  return callProviderAtHost("https://mobile-unlock.com", action, apiKey);
}

async function callProviderCatalogue(action: string, apiKey: string) {
  const hosts = ["https://www.mobile-unlock.com", "https://mobile-unlock.com"];
  const results = await Promise.all(hosts.map(async (host) => {
    try {
      return { host, payload: await callProviderAtHost(host, action, apiKey), error: null as string | null };
    } catch (error) {
      return { host, payload: null as any, error: String(error?.message || "Catalogue request failed.") };
    }
  }));
  const populated = results.find((item) => item.payload && countServices(item.payload) > 0);
  if (populated) return populated.payload;
  const available = results.find((item) => item.payload);
  if (available) return available.payload;
  throw new Error("Both documented and apex Fusion hosts failed: " + results.map((item) => item.host + ": " + item.error).join(" || "));
}

async function callProviderRestAccount(apiKey: string) {
  const response = await fetch("https://mobile-unlock.com/api/v1/account", {
    method: "GET",
    headers: {
      "Authorization": "Bearer " + apiKey,
      "Accept": "application/json",
    },
  });
  const text = await response.text();
  let payload: any;
  try { payload = JSON.parse(text); }
  catch { throw new Error("REST account endpoint returned non-JSON (HTTP " + response.status + ")."); }
  if (!response.ok) {
    const message = payload?.message || payload?.error || "REST account endpoint returned HTTP " + response.status + ".";
    throw new Error(String(message).slice(0, 240));
  }
  return payload;
}

async function callProviderRestServicesAtHost(host: string, apiKey: string) {
  const response = await fetch(host + "/api/v1/services", {
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

async function callProviderRestServices(apiKey: string) {
  const hosts = ["https://www.mobile-unlock.com", "https://mobile-unlock.com"];
  const results = await Promise.all(hosts.map(async (host) => {
    try {
      return { host, payload: await callProviderRestServicesAtHost(host, apiKey), error: null as string | null };
    } catch (error) {
      return { host, payload: null as any, error: String(error?.message || "REST catalogue request failed.") };
    }
  }));
  const populated = results.find((item) => item.payload && countServices(item.payload) > 0);
  if (populated) return populated.payload;
  const available = results.find((item) => item.payload);
  if (available) return available.payload;
  throw new Error("Both REST catalogue hosts failed: " + results.map((item) => item.host + ": " + item.error).join(" || "));
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
    if (!["test_connection", "sync_catalogue", "submit_approved_order"].includes(action)) return json({ ok: false, error: "Unsupported action." }, 400);
    const businessId = String(body.business_id || "");
    if (!businessId) return json({ ok: false, error: "Business ID is required." }, 400);

    const { data: membership, error: membershipError } = await userClient
      .from("business_members").select("role,is_active")
      .eq("business_id", businessId).eq("user_id", authData.user.id).eq("is_active", true).maybeSingle();
    if (membershipError) throw membershipError;
    if (!membership || !["owner", "admin", "manager"].includes(String(membership.role).toLowerCase())) {
      return json({ ok: false, error: "Business owner, administrator or manager access is required." }, 403);
    }

    if (action === "submit_approved_order") {
      if (String(membership.role).toLowerCase() !== "owner") {
        return json({ ok: false, error: "Only the business owner can submit an approved order." }, 403);
      }
      const orderId = String(body.order_id || "");
      if (!orderId) return json({ ok: false, error: "Order ID is required." }, 400);

      // This database RPC checks owner approval, full payment, service mapping,
      // and atomically prevents duplicate submissions before any provider call.
      const { data: order, error: claimError } = await userClient.rpc(
        "claim_phone_unlocking_provider_submission",
        { p_business_id: businessId, p_order_id: orderId },
      );
      if (claimError) throw claimError;
      if (!order || typeof order !== "object") throw new Error("The approved order could not be claimed for submission.");

      const params = new URLSearchParams({
        action: "placeimeiorder",
        apikey: providerKey,
        ID: String(order.provider_service_id),
        IMEI: String(order.imei),
      });
      let response: Response;
      let payload: any;
      try {
        // One request to the provider's documented canonical API host.
        // Never retry automatically: a timeout can occur after the provider accepts an order.
        response = await fetch("https://www.mobile-unlock.com/api/fusion", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json" },
          body: params,
        });
        const responseText = await response.text();
        try { payload = JSON.parse(responseText); }
        catch {
          await userClient.rpc("finish_phone_unlocking_provider_submission", {
            p_business_id: businessId, p_order_id: orderId, p_outcome: "unknown",
            p_provider_reference: null, p_message: "Provider response was not readable JSON; reconcile with provider before retrying.",
          });
          return json({ ok: false, uncertain: true, error: "Provider response could not be confirmed. Check the provider dashboard before any retry." }, 502);
        }
      } catch (error) {
        await userClient.rpc("finish_phone_unlocking_provider_submission", {
          p_business_id: businessId, p_order_id: orderId, p_outcome: "unknown",
          p_provider_reference: null, p_message: "Network/transport outcome is uncertain; reconcile with provider before retrying.",
        });
        return json({ ok: false, uncertain: true, error: "The provider request outcome is uncertain. Check the Mobile-Unlock dashboard before any retry." }, 502);
      }

      const providerProblem = providerError(payload);
      if (providerProblem) {
        const { error: finishError } = await userClient.rpc("finish_phone_unlocking_provider_submission", {
          p_business_id: businessId, p_order_id: orderId, p_outcome: "failed",
          p_provider_reference: null, p_message: providerProblem,
        });
        if (finishError) throw finishError;
        return json({ ok: false, error: "Mobile-Unlock rejected the order: " + providerProblem }, 502);
      }
      if (!response.ok) {
        await userClient.rpc("finish_phone_unlocking_provider_submission", {
          p_business_id: businessId, p_order_id: orderId, p_outcome: "unknown",
          p_provider_reference: null, p_message: "Provider returned HTTP " + response.status + "; acceptance could not be ruled out.",
        });
        return json({ ok: false, uncertain: true, error: "Provider returned HTTP " + response.status + ". Check the provider dashboard before retrying." }, 502);
      }
      const item = successItem(payload);
      const reference = item?.REFERENCEID ?? item?.LIST?.REFERENCEID ?? item?.data?.REFERENCEID;
      if (reference == null || String(reference).trim() === "") {
        await userClient.rpc("finish_phone_unlocking_provider_submission", {
          p_business_id: businessId, p_order_id: orderId, p_outcome: "unknown",
          p_provider_reference: null, p_message: "Provider response did not include a reference ID; reconcile before retrying.",
        });
        return json({ ok: false, uncertain: true, error: "Provider response did not include an order reference. Check the provider dashboard before retrying." }, 502);
      }
      const { error: finishError } = await userClient.rpc("finish_phone_unlocking_provider_submission", {
        p_business_id: businessId, p_order_id: orderId, p_outcome: "submitted",
        p_provider_reference: String(reference), p_message: "Accepted by Mobile-Unlock.",
      });
      if (finishError) throw finishError;
      return json({ ok: true, provider_reference: String(reference), provider_status: item?.STATUS || item?.LIST?.STATUS || "PENDING" });
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
      callProvider("accountinfo", providerKey), callProviderCatalogue("imeiservicelist", providerKey),
      callProviderCatalogue("getserverservicelist", providerKey),
    ]);
    let restAccountPayload: any = null;
    let restAccountError: string | null = null;
    try {
      restAccountPayload = await callProviderRestAccount(providerKey);
    } catch (error) {
      restAccountError = String(error?.message || "REST account request failed.").slice(0, 240);
    }
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
      const restAccountShape = restAccountPayload ? describeShape(restAccountPayload) : "REST account unavailable: " + (restAccountError || "not returned");
      const restShape = restPayload ? describeShape(restPayload) : "REST services unavailable: " + (restError || "not returned");
      const restAccountData = restAccountPayload?.data && typeof restAccountPayload.data === "object" ? restAccountPayload.data : null;
      const accountSummary = restAccountData
        ? "balance=" + (restAccountData.balance ?? restAccountData.credit ?? "unknown") +
          " currency=" + (restAccountData.currency ?? "unknown") +
          " user_type=" + (restAccountData.user_type ?? "unknown") +
          " group=" + (restAccountData.group ?? "unknown") +
          " discount_percent=" + (restAccountData.discount_percent ?? "unknown")
        : "Account details unavailable.";
      throw new Error("No services were returned by the Fusion or REST catalogues. No catalogue records were changed. YOUR ACCOUNT STATUS: " + accountSummary + " — this usually means the provider has not switched on any service groups for this account yet (a zero balance, an unverified/trial account, or a reseller group with no assigned services), not a fault in this app. Check your account status directly at mobile-unlock.com, or contact their support, then try the sync again. ACCOUNT: " + restAccountShape + " || IMEI: " + imeiShape + " || SERVER: " + serverShape + " || REST SERVICES: " + restShape + (restAccountError ? " || REST account error: " + restAccountError : "") + (restError ? " || REST services error: " + restError : ""));
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
