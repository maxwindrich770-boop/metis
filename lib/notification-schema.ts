// Initialized with the core database before requests are accepted. Read-only
// notification feeds and remote delivery checks must never acquire a writer lock.
export const NOTIFICATION_SCHEMA = `
CREATE TABLE IF NOT EXISTS notification_records (
 sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
 owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 title TEXT NOT NULL, body TEXT NOT NULL, chat_id TEXT,
 created_at TEXT NOT NULL, source_key TEXT UNIQUE);
CREATE INDEX IF NOT EXISTS notifications_owner_cursor ON notification_records(owner_id, sequence);
CREATE TABLE IF NOT EXISTS notification_prefs (
 owner_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS notification_observer (key TEXT PRIMARY KEY, cursor INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS notification_deliveries (
 notification_id TEXT NOT NULL REFERENCES notification_records(id) ON DELETE CASCADE,
 client_id TEXT NOT NULL, acknowledged_at TEXT, retry_at INTEGER NOT NULL DEFAULT 0,
 attempts INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(notification_id, client_id));
CREATE TABLE IF NOT EXISTS mobile_devices (
 id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 session_hash TEXT NOT NULL REFERENCES sessions(token_hash) ON DELETE CASCADE,
 installation_id TEXT NOT NULL, topic TEXT NOT NULL, environment TEXT NOT NULL,
 token_digest TEXT NOT NULL, sealed_token TEXT NOT NULL, expires_at INTEGER NOT NULL,
 event_mask INTEGER NOT NULL DEFAULT 15,
 UNIQUE(owner_id, installation_id), UNIQUE(topic, environment, token_digest));
CREATE INDEX IF NOT EXISTS mobile_devices_session ON mobile_devices(session_hash);
CREATE TABLE IF NOT EXISTS mobile_session_revocations (
 session_hash TEXT PRIMARY KEY REFERENCES sessions(token_hash) ON DELETE CASCADE,
 ticket_hash TEXT NOT NULL UNIQUE);
CREATE TABLE IF NOT EXISTS mobile_push_outbox (
 notification_id TEXT NOT NULL REFERENCES notification_records(id) ON DELETE CASCADE,
 device_id TEXT NOT NULL REFERENCES mobile_devices(id) ON DELETE CASCADE,
 retry_at INTEGER NOT NULL DEFAULT 0, attempts INTEGER NOT NULL DEFAULT 0,
 PRIMARY KEY(notification_id, device_id));
CREATE INDEX IF NOT EXISTS mobile_push_outbox_retry ON mobile_push_outbox(retry_at);
CREATE TRIGGER IF NOT EXISTS mobile_push_on_run_notification
AFTER INSERT ON notification_records WHEN NEW.source_key LIKE 'run:%'
BEGIN
 INSERT OR IGNORE INTO mobile_push_outbox(notification_id,device_id)
 SELECT NEW.id, id FROM mobile_devices WHERE owner_id=NEW.owner_id
 AND expires_at > unixepoch() * 1000;
END;
CREATE TRIGGER IF NOT EXISTS mobile_push_on_pending_approval
AFTER INSERT ON pending_approvals WHEN NEW.owner_id IS NOT NULL AND NEW.status='waiting_for_user'
BEGIN
 INSERT OR IGNORE INTO notification_records(id,owner_id,title,body,chat_id,created_at,source_key)
 VALUES(lower(hex(randomblob(16))),NEW.owner_id,'Approval requested','Open the chat to review the request.',
 NEW.chat_id,NEW.created_at,'run:' || NEW.owner_id || ':approval:' || NEW.id);
END;
`;
