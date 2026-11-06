import assert from "node:assert/strict";
import { generateKeyPairSync, randomBytes, randomUUID, verify } from "node:crypto";
import { once } from "node:events";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import http2 from "node:http2";
import { syncBuiltinESMExports } from "node:module";
import os from "node:os";
import path from "node:path";
import test from "node:test";

test("Apple routes isolate accounts, version approvals and retry or revoke encrypted push deliveries", async t => {
  const root = mkdtempSync(path.join(os.tmpdir(), "metis-mobile-test-"));
  Object.assign(process.env, {
    AI_CHAT_ROOT: root, CHAT_DATA_DIR: root, CHAT_DB_PATH: path.join(root, "chat.sqlite"),
    METIS_AI_BOOTSTRAP_PASSWORD: "", METIS_AI_ADMIN_USERNAMES: "", CHAT_LEGACY_HEADER_AUTH: "false",
    METIS_APNS_TOPIC: "dev.metis.fixture", METIS_APNS_KEY_ID: "TESTKEY", METIS_APNS_TEAM_ID: "TESTTEAM",
    METIS_APNS_KEY_PATH: path.join(root, "unused-fixture.p8"), METIS_APNS_ENVIRONMENT: "sandbox",
    METIS_APNS_TOKEN_KEY: "ab".repeat(32),
  });
  const { authenticateUser, createUser, revokeRequestSession } = await import("../lib/auth");
  const { createChat } = await import("../lib/db-store");
  const { appendRunEvent } = await import("../lib/db-jobs");
  const { createApproval } = await import("../lib/db-approvals");
  const { getDatabase } = await import("../lib/sqlite");
  const { createNotification } = await import("../lib/notification-store");
  const { classifyAPNs, deliverMobilePush } = await import("../lib/mobile-push");
  const devices = await import("../app/api/mobile/devices/route");
  const mobileSession = await import("../app/api/mobile/session/route");
  const approvals = await import("../app/api/mobile/approvals/route");
  const notification = await import("../app/api/mobile/notifications/[id]/route");
  const chatEvents = await import("../app/api/chats/events/route");
  const runs = await import("../app/api/runs/route");
  const db = getDatabase();
  try {
    const alice = createUser("metis-mobile-test-alice", "fixture");
    const bob = createUser("metis-mobile-test-bob", "fixture");
    const aliceSession = authenticateUser(alice.username, "fixture")!.token;
    const bobSession = authenticateUser(bob.username, "fixture")!.token;
    const chat = createChat("Alice private", undefined, alice.id);
    const req = (target: string, session?: string, method = "GET", data?: object) => new Request("http://localhost" + target, {
      method, headers: session ? { cookie: "ai_chat_auth=" + session } : undefined,
      body: data === undefined ? undefined : JSON.stringify(data),
    });
    const token = "d0".repeat(32);
    const installationId = randomUUID();
    const registration = { installationId, token, topic: "dev.metis.fixture", environment: "sandbox", events: ["approval", "error"] };
    const devicePath = "/api/mobile/devices";
    assert.equal((await devices.POST(req(devicePath, undefined, "POST", registration))).status, 401);
    assert.equal((await devices.POST(req(devicePath, aliceSession, "POST", { ...registration, environment: "production" }))).status, 503);
    assert.equal((await devices.POST(req(devicePath, aliceSession, "POST", registration))).status, 201);
    const ownDevices = await (await devices.GET(req(devicePath, aliceSession))).json();
    assert.deepEqual(ownDevices.devices[0].events, ["error", "approval"]);
    assert.ok(!JSON.stringify(ownDevices).includes(token));
    assert.deepEqual(await (await devices.GET(req(devicePath, bobSession))).json(), { devices: [] });
    const sealed = db.prepare("SELECT sealed_token, token_digest FROM mobile_devices").get();
    assert.ok(sealed && !JSON.stringify(sealed).includes(token));
    assert.equal((await devices.DELETE(req(devicePath, bobSession, "DELETE", { installationId }))).status, 200);
    assert.equal(db.prepare("SELECT COUNT(*) AS count FROM mobile_devices").get()?.count, 1);

    await t.test("revocation closes open chat and run streams before their next event", async () => {
      const session = authenticateUser(alice.username, "fixture")!.token;
      const jobId = randomUUID();
      appendRunEvent(jobId, chat.id, alice.id, "text", { text: "Before revocation" });
      const chatsResponse = await chatEvents.GET(req("/api/chats/events", session));
      const runResponse = await runs.GET(req(`/api/runs?chatId=${chat.id}&jobId=${jobId}&events=1&stream=1`, session));
      assert.equal(chatsResponse.status, 200);
      assert.equal(runResponse.status, 200);
      const chats = chatsResponse.body!.getReader();
      const run = runResponse.body!.getReader();
      const read = async (reader: ReadableStreamDefaultReader<Uint8Array>) =>
        new TextDecoder().decode((await reader.read()).value);
      try {
        assert.match(await read(chats), /event: ready/);
        assert.match(await read(chats), /retry:/);
        assert.match(await read(run), /Before revocation/);
        revokeRequestSession(req("/api/auth", session));
        createChat("After revocation", undefined, alice.id);
        appendRunEvent(jobId, chat.id, alice.id, "text", { text: "After revocation" });
        for (const reader of [chats, run]) {
          assert.equal(await read(reader), "event: auth-expired\ndata: {}\n\n");
          assert.equal((await reader.read()).done, true);
        }
      } finally {
        await Promise.all([chats.cancel(), run.cancel()]);
      }
      assert.equal((await devices.GET(req(devicePath, aliceSession))).status, 200);
    });

    await t.test("sends a signed and redacted APNs request over HTTP/2", async transport => {
      const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
      writeFileSync(process.env.METIS_APNS_KEY_PATH!, privateKey.export({ type: "pkcs8", format: "pem" }), { mode: 0o600 });
      const notice = createNotification(alice.id, { title: "Private error", body: "Do not send this", chatId: chat.id }, `run:${alice.id}:error:wire`);
      const server = http2.createServer();
      const requests: Array<{ headers: http2.IncomingHttpHeaders; payload: string }> = [];
      server.on("stream", (stream, headers) => {
        let payload = "";
        stream.setEncoding("utf8");
        stream.on("data", chunk => { payload += chunk; });
        stream.on("end", () => {
          requests.push({ headers, payload });
          stream.respond({ ":status": 200 });
          stream.end();
        });
      });
      server.listen(0, "127.0.0.1");
      await once(server, "listening");
      const address = server.address();
      assert.ok(address && typeof address !== "string");
      const realConnect = http2.connect;
      const hosts: string[] = [];
      const redirect = transport.mock.method(http2, "connect", (authority: string | URL) => {
        hosts.push(String(authority));
        return realConnect(`http://127.0.0.1:${address.port}`);
      });
      syncBuiltinESMExports();
      try {
        await deliverMobilePush();
      } finally {
        redirect.mock.restore();
        syncBuiltinESMExports();
        await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
      }
      assert.deepEqual(hosts, ["https://api.sandbox.push.apple.com"]);
      assert.equal(requests.length, 1);
      const { headers, payload } = requests[0];
      assert.equal(headers[":method"], "POST");
      assert.equal(headers[":path"], "/3/device/" + token);
      assert.equal(headers["apns-topic"], registration.topic);
      assert.equal(headers["apns-push-type"], "alert");
      assert.equal(headers["apns-collapse-id"], notice.id);
      assert.deepEqual(JSON.parse(payload), {
        aps: { category: "METIS_UPDATE", alert: { title: "Metis", body: "Open Metis to view an update." } },
        notificationId: notice.id,
      });
      const auth = String(headers.authorization);
      assert.match(auth, /^bearer /);
      const [head, claims, signature] = auth.slice(7).split(".");
      assert.deepEqual(JSON.parse(Buffer.from(head, "base64url").toString()), { alg: "ES256", kid: "TESTKEY" });
      const decoded = JSON.parse(Buffer.from(claims, "base64url").toString());
      assert.equal(decoded.iss, "TESTTEAM");
      assert.ok(Math.abs(Date.now() / 1000 - decoded.iat) < 30);
      assert.ok(verify("sha256", Buffer.from(head + "." + claims),
        { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signature, "base64url")));
      assert.equal(db.prepare("SELECT COUNT(*) AS count FROM mobile_push_outbox").get()?.count, 0);
    });

    const approval = createApproval({ chatId: chat.id, ownerId: alice.id, title: "Review shell command", command: "fixture command" });
    assert.equal((await approvals.GET(req("/api/mobile/approvals?chatId=" + chat.id, bobSession))).status, 404);
    const pending = await approvals.GET(req("/api/mobile/approvals?chatId=" + chat.id, aliceSession));
    assert.equal((await pending.json()).approval.version, 1);
    const input = { approvalId: approval.approvalId, decision: "deny", version: 1 };
    const approvePath = "/api/mobile/approvals";
    assert.equal((await approvals.POST(req(approvePath, aliceSession, "POST", { ...input, decision: "allow-session" }))).status, 400);
    assert.equal((await approvals.POST(req(approvePath, bobSession, "POST", input))).status, 404);
    assert.equal((await approvals.POST(req(approvePath, aliceSession, "POST", { ...input, version: 2 }))).status, 409);
    const decisions = await Promise.all([1, 2].map(() => approvals.POST(req(approvePath, aliceSession, "POST", input))));
    assert.equal(decisions.filter(result => result.status === 200).length, 1);

    const notice = createNotification(alice.id, { title: "Run failed", chatId: chat.id }, `run:${alice.id}:error:fixture`);
    createNotification(alice.id, { title: "Duplicate", chatId: chat.id }, `run:${alice.id}:error:fixture`);
    createNotification(alice.id, { title: "Muted question", chatId: chat.id }, `run:${alice.id}:question:fixture`);
    const params = { params: Promise.resolve({ id: notice.id }) };
    assert.equal((await notification.GET(req("/api/mobile/notifications/" + notice.id, bobSession), params)).status, 404);
    assert.deepEqual(await (await notification.GET(req("/api/mobile/notifications/" + notice.id, aliceSession), params)).json(), { chatId: chat.id });
    const observed: string[] = [];
    await deliverMobilePush(async delivery => {
      assert.equal(delivery.token, token);
      assert.equal(delivery.environment, "sandbox");
      observed.push(delivery.notificationId);
      return "retry";
    });
    assert.equal(observed.length, 2);
    assert.equal(observed.filter(id => id === notice.id).length, 1);
    let prematureRetries = 0;
    await deliverMobilePush(async () => { prematureRetries++; return "retry"; });
    assert.equal(prematureRetries, 0);
    db.exec("UPDATE mobile_push_outbox SET retry_at=0");
    await deliverMobilePush(async () => "revoke");
    assert.equal(db.prepare("SELECT COUNT(*) AS count FROM mobile_devices").get()?.count, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS count FROM mobile_push_outbox").get()?.count, 0);
    assert.equal((await devices.POST(req(devicePath, aliceSession, "POST", registration))).status, 201);
    createNotification(alice.id, { title: "After retry", chatId: chat.id }, `run:${alice.id}:error:logout`);
    const ticket = randomBytes(32).toString("hex");
    assert.equal((await mobileSession.POST(req("/api/mobile/session", undefined, "POST", { ticket }))).status, 401);
    assert.equal((await mobileSession.POST(req("/api/mobile/session", aliceSession, "POST", { ticket }))).status, 200);
    assert.equal((await mobileSession.DELETE(req("/api/mobile/session", undefined, "DELETE", { ticket: "00".repeat(32) }))).status, 200);
    assert.equal(db.prepare("SELECT COUNT(*) AS count FROM mobile_devices").get()?.count, 1);
    assert.equal((await mobileSession.DELETE(req("/api/mobile/session", undefined, "DELETE", { ticket }))).status, 200);
    assert.equal((await mobileSession.DELETE(req("/api/mobile/session", undefined, "DELETE", { ticket }))).status, 200);
    assert.equal(db.prepare("SELECT COUNT(*) AS count FROM mobile_devices").get()?.count, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS count FROM mobile_push_outbox").get()?.count, 0);
    assert.equal(classifyAPNs(400, "BadDeviceToken"), "revoke");
    assert.equal(classifyAPNs(429), "retry");
    assert.equal(classifyAPNs(503), "retry");
    assert.equal(classifyAPNs(200), "sent");
  } finally {
    db.close();
    rmSync(root, { recursive: true, force: true });
  }
});
