// Supabase Edge Function: registration email alerts
// Receives INSERT webhooks from the two platform registration notification tables.
// Secrets required: REGISTRATION_WEBHOOK_SECRET, RESEND_API_KEY,
// RESEND_FROM_EMAIL (must be on a domain verified in Resend), REGISTRATION_ALERT_TO.

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

const escapeHtml = (value: unknown) =>
  String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  const expectedSecret = Deno.env.get("REGISTRATION_WEBHOOK_SECRET") || "";
  const suppliedSecret = req.headers.get("x-webhook-secret") || "";
  if (!expectedSecret || !suppliedSecret || !constantTimeEqual(suppliedSecret, expectedSecret)) {
    return json({ error: "Unauthorized webhook" }, 401);
  }

  const apiKey = Deno.env.get("RESEND_API_KEY") || "";
  const from = Deno.env.get("RESEND_FROM_EMAIL") || "";
  const to = Deno.env.get("REGISTRATION_ALERT_TO") || "";
  if (!apiKey || !from || !to) {
    return json({ error: "Email service is not fully configured" }, 500);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON payload" }, 400);
  }

  const table = String(payload.table || "");
  const eventType = String(payload.type || "");
  const record = (payload.record && typeof payload.record === "object"
    ? payload.record
    : {}) as Record<string, unknown>;

  if (eventType !== "INSERT") return json({ ok: true, ignored: "Non-INSERT event" });
  if (!["platform_registration_notifications", "platform_business_registration_notifications"].includes(table)) {
    return json({ error: "Unsupported source table" }, 400);
  }

  const isBusiness = table === "platform_business_registration_notifications";
  const eventId = String(record.id || record.user_id || record.business_id || "");
  if (!eventId) return json({ error: "Registration record has no event identifier" }, 400);

  const registeredAt = String(record.registered_at || new Date().toISOString());
  const dateLabel = new Date(registeredAt).toLocaleString("en-GB", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "UTC",
  });

  const title = isBusiness ? "New business workspace registered" : "New customer account registered";
  const details = isBusiness
    ? [
        ["Business", record.business_name],
        ["Industry", record.industry],
        ["Owner email", record.owner_email],
        ["Registered (UTC)", dateLabel],
      ]
    : [
        ["Customer name", record.full_name],
        ["Customer email", record.email],
        ["Registered (UTC)", dateLabel],
      ];

  const textBody = [
    title,
    "",
    ...details.map(([label, value]) => `${label}: ${String(value ?? "Not provided")}`),
    "",
    "White Lion SME Business Operating System",
  ].join("\n");

  const htmlRows = details.map(([label, value]) =>
    `<tr><td style="padding:10px 12px;color:#64748b;border-bottom:1px solid #e2e8f0">${escapeHtml(label)}</td><td style="padding:10px 12px;font-weight:600;border-bottom:1px solid #e2e8f0">${escapeHtml(value ?? "Not provided")}</td></tr>`
  ).join("");

  const htmlBody = `<!doctype html><html><body style="margin:0;padding:24px;background:#f1f5f9;font-family:Arial,sans-serif;color:#0f172a"><div style="max-width:600px;margin:auto;background:#fff;border-radius:14px;padding:28px"><div style="font-size:12px;letter-spacing:2px;color:#64748b;font-weight:bold">WHITE LION · PLATFORM ALERT</div><h1 style="font-size:22px;margin:12px 0 8px">${escapeHtml(title)}</h1><p style="color:#64748b;margin:0 0 20px">A new registration has been recorded on your platform.</p><table style="width:100%;border-collapse:collapse">${htmlRows}</table><p style="font-size:12px;color:#94a3b8;margin-top:24px">Automated notification from White Lion SME Business Operating System.</p></div></body></html>`;

  const resendResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": `white-lion-registration-${table}-${eventId}`,
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject: `[White Lion] ${title}`,
      text: textBody,
      html: htmlBody,
    }),
  });

  const result = await resendResponse.json().catch(() => ({}));
  if (!resendResponse.ok) {
    // Return provider error to the webhook log without exposing credentials.
    return json({ error: "Resend rejected the email", provider_status: resendResponse.status, details: result }, 502);
  }

  return json({ ok: true, email_id: result.id || null, event: isBusiness ? "business_registration" : "customer_registration" });
});
