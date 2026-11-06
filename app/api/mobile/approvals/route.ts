import { POST as resolveApproval } from "@/app/api/chat/approval/route";
import { getAuthenticatedCookieUser } from "@/lib/auth";
import { getApproval, getPendingApprovalForChat } from "@/lib/db-approvals";
import { canAccessChat } from "@/lib/project-access";
import { z } from "zod";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const decision = z.object({
  approvalId: z.string().min(1).max(200),
  version: z.number().int().positive(),
  decision: z.enum(["allow", "deny"]),
}).strict();
const headers = { "Cache-Control": "private, no-store" };

export async function GET(req: Request) {
  const owner = getAuthenticatedCookieUser(req)?.id;
  if (!owner) return Response.json({ error: "Unauthorized" }, { status: 401 });
  const chatId = new URL(req.url).searchParams.get("chatId");
  if (!chatId || !canAccessChat(chatId, owner)) return Response.json({ error: "Chat unavailable" }, { status: 404 });
  const pending = getPendingApprovalForChat(chatId, owner);
  const approval = pending && {
    approvalId: pending.approvalId, title: pending.title, command: pending.command,
    files: pending.files, version: pending.version, requiresInAppReview: true,
  };
  return Response.json({ approval }, { headers });
}

export async function POST(req: Request) {
  const owner = getAuthenticatedCookieUser(req)?.id;
  if (!owner) return Response.json({ error: "Unauthorized" }, { status: 401 });
  const input = decision.safeParse(await req.clone().json().catch(() => null));
  if (!input.success) return Response.json({ error: "Invalid versioned decision" }, { status: 400 });
  const approval = getApproval(input.data.approvalId, owner);
  if (!approval || !canAccessChat(approval.chatId, owner)) return Response.json({ error: "Approval unavailable" }, { status: 404 });
  if (approval.status !== "waiting_for_user" || approval.version !== input.data.version) {
    return Response.json({ error: "Approval changed. Refresh the chat." }, { status: 409 });
  }
  // The existing resolver owns the atomic version transition, expiry and run wakeup.
  const cleanHeaders = new Headers(req.headers);
  cleanHeaders.delete("x-chat-password");
  cleanHeaders.delete("x-chat-username");
  return resolveApproval(new Request(req, { headers: cleanHeaders }));
}
