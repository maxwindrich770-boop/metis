import { createCipheriv, createDecipheriv, createHash, createPrivateKey, randomBytes, randomUUID, sign } from "node:crypto";
import { readFileSync } from "node:fs";
import { connect } from "node:http2";
import { z } from "zod";
import { getNotificationPrefs } from "@/lib/notification-store";
import { canAccessChat } from "@/lib/project-access";
import { getDatabase, transaction } from "@/lib/sqlite";

export const installationId = z.uuid();
const pushKinds = ["done", "error", "question", "approval"] as const;
export const mobileDeviceInput = z.object({
  installationId,
  topic: z.string().min(3).max(200).regex(/^[A-Za-z0-9.-]+$/),
  environment: z.enum(["sandbox", "production"]),
  token: z.string().min(32).max(512).regex(/^(?:[0-9a-fA-F]{2})+$/),
  events: z.array(z.enum(pushKinds)).max(pushKinds.length).optional(),
}).strict();

type DeviceInput = z.infer<typeof mobileDeviceInput>;
const day = 86_400_000;
const appleHosts = { sandbox: "https://api.sandbox.push.apple.com", production: "https://api.push.apple.com" };

function config() {
  const topic = process.env.METIS_APNS_TOPIC?.trim();
  const keyId = process.env.METIS_APNS_KEY_ID?.trim();
  const teamId = process.env.METIS_APNS_TEAM_ID?.trim();
  const keyPath = process.env.METIS_APNS_KEY_PATH?.trim();
  const tokenKey = process.env.METIS_APNS_TOKEN_KEY?.trim();
  if (!topic || !keyId || !teamId || !keyPath || !tokenKey || !/^[a-fA-F0-9]{64}$/.test(tokenKey)) return null;
  const environment = process.env.METIS_APNS_ENVIRONMENT?.trim() || "production";
  if (environment !== "sandbox" && environment !== "production") return null;
  return { topic, keyId, teamId, keyPath, environment, tokenKey: Buffer.from(tokenKey, "hex") };
}

export function mobilePushAvailable() { return config() !== null; }

function seal(token: string, key: Buffer, deviceId: string) {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  cipher.setAAD(Buffer.from(deviceId));
  const encrypted = Buffer.concat([cipher.update(token, "utf8"), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), encrypted]).toString("base64");
}

function unseal(value: string, key: Buffer, deviceId: string) {
  const bytes = Buffer.from(value, "base64");
  const cipher = createDecipheriv("aes-256-gcm", key, bytes.subarray(0, 12));
  cipher.setAAD(Buffer.from(deviceId));
  cipher.setAuthTag(bytes.subarray(12, 28));
  return Buffer.concat([cipher.update(bytes.subarray(28)), cipher.final()]).toString("utf8");
}

export function registerMobileDevice(owner: string, sessionHash: string, input: DeviceInput) {
  const settings = config();
  if (!settings || settings.topic !== input.topic || settings.environment !== input.environment) return "unsupported";
  const token = input.token.toLowerCase();
  const digest = createHash("sha256").update(token).digest("hex");
  const install = input.installationId.toLowerCase();
  const now = Date.now();
  let eventMask = 0;
  for (const kind of input.events ?? pushKinds) eventMask |= 1 << pushKinds.indexOf(kind);
  return transaction(() => {
    const db = getDatabase();
    const session = db.prepare("SELECT expires_at AS expiresAt FROM sessions WHERE token_hash=? AND user_id=? AND expires_at>?")
      .get(sessionHash, owner, new Date(now).toISOString()) as {expiresAt: string} | undefined;
    if (!session) return "unauthorized";
    db.prepare("DELETE FROM mobile_devices WHERE expires_at<=?").run(now);
    const existing = db.prepare("SELECT id, token_digest AS digest FROM mobile_devices WHERE owner_id=? AND installation_id=?")
      .get(owner, install) as {id: string; digest: string} | undefined;
    const count = db.prepare("SELECT COUNT(*) AS count FROM mobile_devices WHERE owner_id=?").get(owner) as {count: number};
    if (!existing && count.count >= 20) return "limit";
    // Moving a physical installation to another account deletes its previous outbox.
    db.prepare("DELETE FROM mobile_devices WHERE topic=? AND environment=? AND token_digest=? AND (owner_id<>? OR installation_id<>?)")
      .run(input.topic, input.environment, digest, owner, install);
    if (existing && existing.digest !== digest) db.prepare("DELETE FROM mobile_devices WHERE id=?").run(existing.id);
    const id = existing?.digest === digest ? existing.id : randomUUID();
    db.prepare(`INSERT INTO mobile_devices(id,owner_id,session_hash,installation_id,topic,environment,token_digest,sealed_token,expires_at,event_mask)
      VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET session_hash=excluded.session_hash,
      sealed_token=excluded.sealed_token,expires_at=excluded.expires_at,event_mask=excluded.event_mask`)
      .run(id, owner, sessionHash, install, input.topic, input.environment, digest, seal(token, settings.tokenKey, id),
        Date.parse(session.expiresAt), eventMask);
    return "registered";
  });
}

export function revokeMobileDevice(owner: string, installation: string) {
  getDatabase().prepare("DELETE FROM mobile_devices WHERE owner_id=? AND installation_id=?").run(owner, installation.toLowerCase());
}

export function listMobileDevices(owner: string) {
  const rows = getDatabase().prepare(`SELECT installation_id AS id,environment,expires_at AS expiresAt,event_mask AS eventMask
    FROM mobile_devices WHERE owner_id=? AND expires_at>? ORDER BY expires_at DESC`).all(owner, Date.now()) as Array<{
      id: string; environment: string; expiresAt: number; eventMask: number;
    }>;
  return rows.map(({ eventMask, ...device }) => ({ ...device, events: pushKinds.filter((_, index) => Boolean(eventMask & (1 << index))) }));
}

type Delivery = { notificationId: string; token: string; topic: string; environment: keyof typeof appleHosts };
type AppleResult = "sent" | "retry" | "revoke" | "discard";
let jwt: { value: string; expires: number; key: string } | undefined;

function authorization(settings: NonNullable<ReturnType<typeof config>>) {
  const key = [settings.teamId, settings.keyId, settings.keyPath].join(":");
  if (jwt?.key === key && jwt.expires > Date.now()) return jwt.value;
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const input = encode({ alg: "ES256", kid: settings.keyId }) + "." + encode({ iss: settings.teamId, iat: Math.floor(Date.now() / 1000) });
  const signature = sign("sha256", Buffer.from(input), {
    key: createPrivateKey(readFileSync(settings.keyPath)), dsaEncoding: "ieee-p1363",
  }).toString("base64url");
  const value = "bearer " + input + "." + signature;
  jwt = { value, expires: Date.now() + 45 * 60_000, key };
  return value;
}

export function classifyAPNs(status: number, reason?: string): AppleResult {
  if (status === 200) return "sent";
  if (status === 410 || reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic") return "revoke";
  if (status === 0 || status === 429 || status >= 500 || status === 403) return "retry";
  return "discard";
}

async function sendAPNs(delivery: Delivery, settings: NonNullable<ReturnType<typeof config>>): Promise<AppleResult> {
  const bearer = authorization(settings);
  return new Promise(resolve => {
    const client = connect(appleHosts[delivery.environment]);
    let finished = false;
    const finish = (result: AppleResult) => {
      if (finished) return;
      finished = true;
      clearTimeout(timeout);
      client.destroy();
      resolve(result);
    };
    const timeout = setTimeout(() => finish("retry"), 8000);
    client.once("error", () => finish("retry"));
    let request;
    try {
      request = client.request({
        ":method": "POST", ":path": "/3/device/" + delivery.token,
        authorization: bearer, "apns-topic": delivery.topic, "apns-push-type": "alert",
        "content-type": "application/json",
        "apns-collapse-id": delivery.notificationId, "apns-expiration": String(Math.floor(Date.now() / 1000) + 3600),
      });
    } catch {
      finish("retry");
      return;
    }
    let status = 0;
    let body = "";
    request.setEncoding("utf8");
    request.on("response", headers => { status = Number(headers[":status"]); });
    request.on("data", chunk => { if (body.length < 4096) body += chunk; });
    request.once("error", () => finish("retry"));
    request.once("end", () => {
      let reason: string | undefined;
      try { reason = JSON.parse(body).reason; } catch {}
      finish(classifyAPNs(status, reason));
    });
    request.end(JSON.stringify({
      aps: { category: "METIS_UPDATE", alert: { title: "Metis", body: "Open Metis to view an update." } },
      notificationId: delivery.notificationId,
    }));
  });
}

export async function deliverMobilePush(send?: (delivery: Delivery) => Promise<AppleResult>) {
  const settings = config();
  if (!settings) return;
  const db = getDatabase();
  const rows = db.prepare(`SELECT o.notification_id AS notificationId,o.device_id AS deviceId,o.attempts,
    d.owner_id AS ownerId,d.sealed_token AS sealedToken,d.topic,d.environment,d.expires_at AS expiresAt,d.event_mask AS eventMask,
    n.created_at AS createdAt,n.chat_id AS chatId,n.source_key AS sourceKey
    FROM mobile_push_outbox o JOIN mobile_devices d ON d.id=o.device_id
    JOIN notification_records n ON n.id=o.notification_id AND n.owner_id=d.owner_id
    WHERE o.retry_at<=? ORDER BY o.retry_at,n.sequence LIMIT 8`).all(Date.now()) as Array<{
      notificationId: string; deviceId: string; attempts: number; ownerId: string; sealedToken: string;
      topic: string; environment: Delivery["environment"]; expiresAt: number; createdAt: string;
      chatId: string | null; sourceKey: string; eventMask: number;
    }>;
  const remove = db.prepare("DELETE FROM mobile_push_outbox WHERE notification_id=? AND device_id=?");
  await Promise.all(rows.map(async row => {
    const now = Date.now();
    const kind = pushKinds.findIndex(value => row.sourceKey.startsWith(`run:${row.ownerId}:${value}:`));
    if (row.expiresAt <= now || now - Date.parse(row.createdAt) > day || row.attempts >= 9 ||
      kind < 0 || !(row.eventMask & (1 << kind)) ||
      row.topic !== settings.topic || row.environment !== settings.environment ||
      (row.chatId && !canAccessChat(row.chatId, row.ownerId)) ||
      (row.sourceKey.startsWith(`run:${row.ownerId}:done:`) && !getNotificationPrefs(row.ownerId).agentFinishedEnabled)) {
      remove.run(row.notificationId, row.deviceId);
      return;
    }
    const claim = db.prepare(`UPDATE mobile_push_outbox SET retry_at=?,attempts=attempts+1
      WHERE notification_id=? AND device_id=? AND retry_at<=? AND attempts=?`)
      .run(now + Math.min(3600_000, 30_000 * 2 ** row.attempts), row.notificationId, row.deviceId, now, row.attempts);
    if (!claim.changes) return;
    let result: AppleResult = "retry";
    try {
      const token = unseal(row.sealedToken, settings.tokenKey, row.deviceId);
      const delivery = { token, notificationId: row.notificationId, topic: row.topic, environment: row.environment };
      result = await (send ? send(delivery) : sendAPNs(delivery, settings));
    } catch { /* Retry boundedly without including secrets in logs. */ }
    if (result === "revoke") db.prepare("DELETE FROM mobile_devices WHERE id=? AND sealed_token=?").run(row.deviceId, row.sealedToken);
    if (result !== "retry") remove.run(row.notificationId, row.deviceId);
  }));
}

export function mobileNotificationChat(owner: string, id: string) {
  const row = getDatabase().prepare("SELECT chat_id AS chatId FROM notification_records WHERE id=? AND owner_id=?")
    .get(id, owner) as {chatId: string | null} | undefined;
  return row?.chatId && canAccessChat(row.chatId, owner) ? row.chatId : null;
}
