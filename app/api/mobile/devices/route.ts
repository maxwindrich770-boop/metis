import { getAuthenticatedCookieUser, getRequestSessionHash } from "@/lib/auth";
import { installationId, listMobileDevices, mobileDeviceInput, registerMobileDevice, revokeMobileDevice } from "@/lib/mobile-push";
import { consumeRateLimit } from "@/lib/rate-limit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const owner = getAuthenticatedCookieUser(req)?.id;
  if (!owner) return Response.json({ error: "Unauthorized" }, { status: 401 });
  return Response.json({ devices: listMobileDevices(owner) }, { headers: { "Cache-Control": "private, no-store" } });
}

export async function POST(req: Request) {
  const owner = getAuthenticatedCookieUser(req)?.id;
  const session = getRequestSessionHash(req);
  if (!owner || !session) return Response.json({ error: "Unauthorized" }, { status: 401 });
  const limit = consumeRateLimit(`mobile-device:${owner}`, 30, 60_000);
  if (!limit.allowed) return Response.json({ error: "Too many registrations" }, {
    status: 429, headers: { "Retry-After": String(limit.retryAfterSeconds) },
  });
  const input = mobileDeviceInput.safeParse(await req.json().catch(() => null));
  if (!input.success) return Response.json({ error: "Invalid registration" }, { status: 400 });
  const result = registerMobileDevice(owner, session, input.data);
  if (result === "unauthorized") return Response.json({ error: "Unauthorized" }, { status: 401 });
  if (result === "unsupported") return Response.json({ error: "Push is unavailable for this app" }, { status: 503 });
  if (result === "limit") return Response.json({ error: "Device limit reached" }, { status: 409 });
  return Response.json({ ok: true }, { status: 201, headers: { "Cache-Control": "private, no-store" } });
}

export async function DELETE(req: Request) {
  const owner = getAuthenticatedCookieUser(req)?.id;
  if (!owner) return Response.json({ error: "Unauthorized" }, { status: 401 });
  const body = await req.json().catch(() => null);
  const id = installationId.safeParse(body?.installationId);
  if (!id.success) return Response.json({ error: "Invalid installation" }, { status: 400 });
  revokeMobileDevice(owner, id.data);
  return Response.json({ ok: true });
}
