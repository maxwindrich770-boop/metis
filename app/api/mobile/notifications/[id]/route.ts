import { getAuthenticatedCookieUser } from "@/lib/auth";
import { mobileNotificationChat } from "@/lib/mobile-push";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request, context: { params: Promise<{ id: string }> }) {
  const owner = getAuthenticatedCookieUser(req)?.id;
  if (!owner) return Response.json({ error: "Unauthorized" }, { status: 401 });
  const chatId = mobileNotificationChat(owner, (await context.params).id);
  return chatId
    ? Response.json({ chatId }, { headers: { "Cache-Control": "private, no-store" } })
    : Response.json({ error: "Notification unavailable" }, { status: 404 });
}
