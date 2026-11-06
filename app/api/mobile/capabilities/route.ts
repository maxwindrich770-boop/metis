import { getAuthenticatedCookieUser } from "@/lib/auth";
import { mobilePushAvailable } from "@/lib/mobile-push";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  if (!getAuthenticatedCookieUser(req)) return Response.json({ error: "Unauthorized" }, { status: 401 });
  return Response.json({ version: 1, apns: mobilePushAvailable() }, { headers: { "Cache-Control": "private, no-store" } });
}
