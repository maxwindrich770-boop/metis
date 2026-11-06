import { createHash } from "node:crypto";
import { getAuthenticatedCookieUser, getRequestSessionHash } from "@/lib/auth";
import { consumeRateLimit, requestClientAddress } from "@/lib/rate-limit";
import { getDatabase } from "@/lib/sqlite";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const account = getAuthenticatedCookieUser(req);
  if (!account) return Response.json({ error: "Unauthorized" }, { status: 401 });
  return Response.json({ username: account.username }, { headers: { "Cache-Control": "private, no-store" } });
}

async function readTicket(req: Request) {
  const body = await req.json().catch(() => null);
  const ticket = typeof body?.ticket === "string" ? body.ticket : "";
  return /^[a-f0-9]{64}$/.test(ticket) ? createHash("sha256").update(ticket).digest("hex") : null;
}

export async function POST(req: Request) {
  const owner = getAuthenticatedCookieUser(req)?.id;
  const session = getRequestSessionHash(req);
  if (!owner || !session) return Response.json({ error: "Unauthorized" }, { status: 401 });
  const ticketHash = await readTicket(req);
  if (!ticketHash) return Response.json({ error: "Invalid revocation ticket" }, { status: 400 });
  const db = getDatabase();
  const result = db.prepare(`INSERT OR IGNORE INTO mobile_session_revocations(session_hash,ticket_hash)
    SELECT token_hash,? FROM sessions WHERE token_hash=? AND user_id=? AND expires_at>?
    AND NOT EXISTS(SELECT 1 FROM mobile_session_revocations WHERE ticket_hash=? AND session_hash<>?)
    ON CONFLICT(session_hash) DO UPDATE SET ticket_hash=excluded.ticket_hash`)
    .run(ticketHash, session, owner, new Date().toISOString(), ticketHash, session);
  if (!result.changes) {
    return Response.json({ error: "Ticket unavailable" }, { status: 409 });
  }
  return Response.json({ ok: true }, { headers: { "Cache-Control": "private, no-store" } });
}

export async function DELETE(req: Request) {
  const limit = consumeRateLimit(`mobile-revoke:${requestClientAddress(req)}`, 120, 60_000);
  if (!limit.allowed) return Response.json({ error: "Too many attempts" }, {
    status: 429, headers: { "Retry-After": String(limit.retryAfterSeconds) },
  });
  const ticketHash = await readTicket(req);
  if (!ticketHash) return Response.json({ error: "Invalid revocation ticket" }, { status: 400 });
  // Return the same result for a redeemed, expired or unknown ticket.
  getDatabase().prepare(`DELETE FROM sessions WHERE token_hash IN (
    SELECT session_hash FROM mobile_session_revocations WHERE ticket_hash=?)`).run(ticketHash);
  return Response.json({ ok: true }, { headers: { "Cache-Control": "private, no-store" } });
}
