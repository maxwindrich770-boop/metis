// Exercise the real Metis handlers and worker over loopback with a disposable
// SQLite database and a deterministic model fixture.
import { once } from "node:events";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir, userInfo } from "node:os";
import path from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

async function main() {
  const root = mkdtempSync(path.join(tmpdir(), "metis-apple-fixture-"));
  const workspace = path.join(root, "model-workspace");
  const defaultWorkspace = path.join(root, "unmapped-workspace");
  for (const folder of [workspace, defaultWorkspace]) mkdirSync(folder, { mode: 0o700 });
  process.on("exit", () => rmSync(root, { recursive: true, force: true }));
  const port = Number(process.argv[2] ?? 43100);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error("Invalid fixture port");
  Object.assign(process.env, {
    AI_CHAT_ROOT: root, AI_CHAT_INSTALL_DIR: process.cwd(), CHAT_DATA_DIR: root,
    CHAT_DB_PATH: path.join(root, "chat.sqlite"), AI_CHAT_MCP_STATE_DIR: path.join(root, "mcp-state"),
    AGENT_CWD: defaultWorkspace, MCP_ENABLE_OPTIONAL_SERVERS: "false", MCP_ENABLE_REMOTE_SERVERS: "false",
    CHAT_LEGACY_HEADER_AUTH: "false", METIS_AI_BOOTSTRAP_PASSWORD: "",
    METIS_AI_ADMIN_USERNAMES: "", AI_CHAT_TRUSTED_PROXIES: "", AI_CHAT_ALLOW_ROOT_AGENTS: "false",
    AI_CHAT_PUBLIC_URL: `http://localhost:${port}`, AI_CHAT_INTERNAL_ORIGIN: `http://127.0.0.1:${port}`,
    MCP_PUBLIC_URL: `http://127.0.0.1:${port}`, MCP_BEARER_TOKEN: "",
    AI_CHAT_INTERNAL_MCP_SERVER: path.resolve("lib/internal-mcp-server.mjs"),
  });
  const { createUser } = await import("../../../lib/auth");
  const { createChat, appendMessage } = await import("../../../lib/db-store");
  const { getDatabase } = await import("../../../lib/sqlite");
  const auth = await import("../../../app/api/auth/route");
  const chats = await import("../../../app/api/chats/route");
  const chat = await import("../../../app/api/chats/[id]/route");
  const submit = await import("../../../app/api/chat/route");
  const cancel = await import("../../../app/api/chat/cancel/route");
  const events = await import("../../../app/api/chats/events/route");
  const fileUploads = await import("../../../app/api/file-uploads/route");
  const fileUpload = await import("../../../app/api/file-uploads/[id]/route");
  const storedUpload = await import("../../../app/api/uploads/[chatId]/[name]/route");
  const models = await import("../../../app/api/models/route");
  const notifications = await import("../../../app/api/notifications/inbox/route");
  const projects = await import("../../../app/api/projects/route");
  const mobileDevices = await import("../../../app/api/mobile/devices/route");
  const mobileSession = await import("../../../app/api/mobile/session/route");
  const { upsertProviderConnection } = await import("../../../lib/provider-connections");
  const { claimNextJob } = await import("../../../lib/db-jobs");
  const { runJobById } = await import("../../../lib/worker-runner");
  const { ensureUserAccess } = await import("../../../lib/user-access");
  const { ensureAllModelAccess } = await import("../../../lib/model-access");
  const runs = await import("../../../app/api/runs/route");

  const alice = createUser("metis-apple-fixture-alice", "apple-fixture-only");
  const bob = createUser("metis-apple-fixture-bob", "apple-fixture-only");
  const db = getDatabase();
  db.prepare("UPDATE users SET is_admin=1 WHERE id=?").run(alice.id);
  ensureUserAccess(alice.id, workspace, userInfo().username);
  ensureAllModelAccess(alice.id);
  upsertProviderConnection(alice.id, {
    providerKey: "compatible", slug: "fixture", label: "Fixture model", authType: "local",
    baseUrl: `http://127.0.0.1:${port}/fixture-provider`, config: { modelIds: ["metis-fixture"] },
  });
  const thread = createChat("Fixture chat", undefined, alice.id);
  createChat("Other user's chat", undefined, bob.id);
  for (let index = 1; index <= 75; index++) {
    appendMessage(thread.id, { role: index % 2 ? "user" : "assistant", content: `Nachricht ${index} 🌱` }, alice.id);
  }
  const now = new Date().toISOString();
  const job = { id: "fixture-run", chatId: thread.id, userId: alice.id, status: "completed" };
  db.prepare("INSERT INTO jobs (id, chat_id, user_id, data, status, updated_at) VALUES (?, ?, ?, ?, ?, ?)")
    .run(job.id, thread.id, alice.id, JSON.stringify(job), job.status, now);
  const insertEvent = db.prepare("INSERT INTO run_events (job_id, chat_id, user_id, event, data, created_at) VALUES (?, ?, ?, ?, ?, ?)");
  insertEvent.run(job.id, thread.id, alice.id, "text", JSON.stringify({ text: "Grüße 🌱" }), now);
  insertEvent.run(job.id, thread.id, alice.id, "text", JSON.stringify({ text: " from Metis" }), now);

  const droppedReplies = new Set<string>();
  let delayedHistory: { chatId: string; jobId: string } | undefined;
  let offline = false;
  const server = createServer(async (incoming, outgoing) => {
    const abort = new AbortController();
    outgoing.once("close", () => abort.abort());
    try {
      const url = new URL(incoming.url ?? "/", `http://localhost:${port}`);
      const method = incoming.method;
      if (url.pathname === "/fixture-control" && method === "POST") {
        const state = url.searchParams.get("state");
        if (state === "offline" || state === "online") offline = state === "offline";
        else if (state === "revoke") {
          db.prepare("DELETE FROM sessions WHERE user_id=?").run(alice.id);
          createChat("Fixture post-revocation signal", undefined, alice.id);
        }
        else { outgoing.writeHead(400).end(); return; }
        console.warn(`Fixture session test control: ${state}`);
        outgoing.writeHead(204).end();
        return;
      }
      if (offline) { outgoing.destroy(); return; }
      if (url.pathname === "/fixture-provider/models" && method === "GET") {
        outgoing.writeHead(200, { "content-type": "application/json" });
        outgoing.end(JSON.stringify({ object: "list", data: [{ id: "metis-fixture", object: "model" }] }));
        return;
      }
      const body = method && ["POST", "PUT", "DELETE", "PATCH"].includes(method)
        ? await Array.fromAsync(incoming) : undefined;
      const request = new Request(url, {
        method,
        headers: new Headers(incoming.headers as Record<string, string>),
        body: body ? Buffer.concat(body) : undefined,
        signal: abort.signal,
      });
      if (url.pathname === "/fixture-provider/chat/completions" && method === "POST") {
        outgoing.writeHead(200, { "content-type": "text/event-stream" });
        const chunk = (delta: object, finish: string | null) =>
          `data: ${JSON.stringify({ id: "fixture-completion", object: "chat.completion.chunk", created: 1,
            model: "metis-fixture", choices: [{ index: 0, delta, finish_reason: finish }] })}\n\n`;
        // Leave enough visible text for the adapter's raw tool-marker lookahead.
        outgoing.write(chunk({ role: "assistant", content: "Live fixture streamed before the run completed. " }, null));
        await new Promise(resolve => setTimeout(resolve, 8_000));
        outgoing.write(chunk({ content: "Final response 🌱" }, null));
        outgoing.end(chunk({}, "stop") + "data: [DONE]\n\n");
        return;
      }
      const match = /^\/api\/chats\/([^/]+)$/.exec(url.pathname);
      const upload = /^\/api\/file-uploads\/([^/]+)$/.exec(url.pathname);
      const download = /^\/api\/uploads\/([^/]+)\/([^/]+)$/.exec(url.pathname);
      let response: Response;
      if (url.pathname === "/api/auth" && method === "POST") {
        const credentials = await request.clone().json().catch(() => null);
        if (credentials?.username === "metis-apple-fixture-redirect") {
          response = new Response(null, { status: 307, headers: { Location: "/fixture-redirect-target" } });
        } else {
          response = await auth.POST(request);
        }
      }
      else if (url.pathname === "/api/auth" && method === "DELETE") response = await auth.DELETE(request);
      else if (url.pathname === "/api/chats" && method === "GET") response = await chats.GET(request);
      else if (url.pathname === "/api/chats" && method === "POST") response = await chats.POST(request);
      else if (url.pathname === "/api/chats/events" && method === "GET") response = await events.GET(request);
      else if (url.pathname === "/api/chat" && method === "POST") {
        const submission = await request.clone().json().catch(() => null);
        response = await submit.POST(request);
        const accepted = response.status === 202 ? await response.clone().json() : null;
        if (accepted && typeof accepted.jobId === "string") {
          const entry = db.prepare("SELECT json_extract(data,'$.modelId') AS modelId FROM jobs WHERE id=?")
            .get(accepted.jobId);
          if (typeof entry?.modelId === "string" && entry.modelId.endsWith(":metis-fixture")) {
            const job = claimNextJob();
            if (job && job.id === accepted.jobId) void runJobById(job.id).catch(error => console.error(error));
          }
          if (submission?.message === "Hello from the iPhone simulator" && !droppedReplies.has(accepted.jobId)) {
            droppedReplies.add(accepted.jobId);
            delayedHistory = { chatId: submission.chatId, jobId: accepted.jobId };
            console.warn("Fixture dropped the first reply after committing the chat job");
            outgoing.writeHead(202, { "content-type": "application/json", "content-length": "512" });
            outgoing.write("{", () => outgoing.destroy());
            return;
          }
        }
      }
      else if (url.pathname === "/api/models" && method === "GET") response = await models.GET(request);
      else if (url.pathname === "/api/notifications/inbox" && method === "GET") response = await notifications.GET(request);
      else if (url.pathname === "/api/projects" && method === "GET") response = await projects.GET(request);
      else if (url.pathname === "/api/mobile/devices" && method === "GET") response = await mobileDevices.GET(request);
      else if (url.pathname === "/api/mobile/session" && (method === "GET" || method === "POST" || method === "DELETE")) {
        response = await mobileSession[method](request);
      }
      else if (url.pathname === "/api/chat/cancel" && method === "POST") response = await cancel.POST(request);
      else if (url.pathname === "/api/file-uploads" && method === "POST") response = await fileUploads.POST(request);
      else if (upload && (method === "PUT" || method === "POST" || method === "DELETE")) {
        response = await fileUpload[method](request, { params: Promise.resolve({ id: decodeURIComponent(upload[1]) }) });
      }
      else if (download && method === "GET") response = await storedUpload.GET(request, {
        params: Promise.resolve({ chatId: decodeURIComponent(download[1]), name: decodeURIComponent(download[2]) }),
      });
      else if (match && method === "GET") {
        const id = decodeURIComponent(match[1]);
        response = await chat.GET(request, { params: Promise.resolve({ id }) });
        if (response.ok && delayedHistory?.chatId === id &&
            db.prepare("SELECT status FROM jobs WHERE id=?").get(delayedHistory.jobId)?.status === "completed") {
          delayedHistory = undefined;
          console.warn("Fixture delayed the saved transcript after the streamed reply");
          await new Promise(resolve => setTimeout(resolve, 4_000));
        }
      }
      else if (url.pathname === "/api/runs" && method === "GET") response = await runs.GET(request);
      else response = new Response(null, { status: 404 });
      if (process.env.METIS_FIXTURE_LOG_REQUESTS === "1" || response.status >= 500) {
        console.warn(`Fixture ${method} ${url.pathname} returned ${response.status}`);
        if (url.pathname === "/api/runs" && url.searchParams.get("stream") === "1") {
          console.warn(`Fixture run stream after cursor ${Number(url.searchParams.get("after"))}`);
        }
        if (url.pathname === "/api/models" && response.ok) {
          const catalog = await response.clone().json();
          console.warn(`Fixture catalog: ${catalog.models.length} model(s), default configured: ${Boolean(catalog.defaultModelId)}`);
        }
      }
      outgoing.writeHead(response.status, Object.fromEntries(response.headers));
      if (response.body) await pipeline(Readable.fromWeb(response.body as import("node:stream/web").ReadableStream), outgoing);
      else outgoing.end();
    } catch (error) {
      if (abort.signal.aborted) return;
      console.error(error);
      if (!outgoing.headersSent) outgoing.writeHead(500);
      outgoing.end();
    }
  });
  server.listen(port, "127.0.0.1");
  await once(server, "listening");
  console.log(`Metis fixture listening on http://localhost:${port}`);
  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.once(signal, () => server.close(() => process.exit(0)));
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
