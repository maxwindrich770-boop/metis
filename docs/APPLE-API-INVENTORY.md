# Apple client API inventory

Source baseline: `master` at `a5a70d4bbcb56c9a8cf582d37e3a7467840d35ce`.
The Swift client uses the existing auth, chat, run, model, project, notification
and attachment routes. New mobile routes expose versioned capabilities for APNs
and approval review. Verify wire compatibility against each supported server
release.

## Login and read-only chats

| Request | Response and errors |
| --- | --- |
| `POST /api/auth` with `{"username":"example","password":"<test password>"}` | `200 {"ok":true}` plus `Set-Cookie`. Invalid body 400, invalid credentials 401, throttled 429 with integer `Retry-After`, storage failure 500. |
| `DELETE /api/auth` | `200 {"ok":true}`, revokes the presented session and expires its cookie. Also succeeds without a valid session. |
| `GET /api/chats` | `200 {"chats":[{"id":"chat-id","title":"Example","createdAt":"…","updatedAt":"…"}]}`. The server orders by pin and activity and includes chats accessible through project membership. Incognito and automation entries are excluded. `includeArchived=true` includes archived entries. 401 or 500. |
| `GET /api/chats/chat-id?messageLimit=30` | `200 {"chat":{"id":"chat-id","messages":[{"id":"message-id","role":"user","content":"Hello"}]},"hasEarlierMessages":true,"nextMessageBefore":30,...}`. Use `messageBefore=30` for the earlier page. Each page is chronological. Default 10, maximum 100, also capped by a byte budget. 401, 404 for a missing or inaccessible chat, 503 with `Retry-After: 1` during projection rebuild, or 304 for a matching ETag. `messageOffset` is available but shifts under appends. |

The cookie is `ai_chat_auth`, HttpOnly, SameSite=Lax and path `/`, with
Secure determined by [request network handling](../lib/request-network.ts).
The [auth store](../lib/auth.ts) stores a hash of a random token in SQLite with
a 30-day expiry. Login revokes a presented old session. Logout revokes the
presented session. Password changes revoke account sessions. A shared password
and legacy auth headers are unnecessary. Login limits are 30 per address, 10
per normalized username and 300 globally per 15 minutes.

The inspected HTTP login and chat read handlers do not require a browser
Origin header. The explicit Origin gate in [server.mjs](../server.mjs) for
browser-stream WebSockets is a separate transport. A reverse proxy may impose
its own checks. Release clients require trusted HTTPS. Native API requests
reject redirects, including redirects from an incorrectly configured upstream.

The iPhone also offers **Sign in on server page**. It shows the selected
server's normal sign-in in an isolated, nonpersistent WebKit view. Page
navigation stays on the selected origin; the app does not fill the server
form or copy its credentials. Only the validated first-party Metis cookie
can cross back into the native client, and `GET /api/chats` must succeed before
the app saves the session. This does not bypass failed credentials, external
identity-provider redirects, certificate checks, or an incompatible chat API.
Native login distinguishes a rejected login request from a rejected session.

Long text and tool payloads may be projected into deferred content/event URLs.
The current client shows the text preview and a web hint. It does not fetch
server-provided links, render tool events, or fetch attachments.

## Run, chat sync and future operations

| Request | Contract at the pinned revision |
| --- | --- |
| `POST /api/chats` | Optional title, model/params, mode/runtime, project and incognito settings. Returns `201 {chat}`. The server owns project authorization. |
| `POST /api/chat` | Canonical web and mobile submission. Takes `{chatId,messageId,message,modelId?,uploadIds?}` and returns `202 {jobId,runId,status,queueMessage?}`. Replaying the same owned message ID returns the accepted job without appending or reopening the run. Distinct concurrent submissions can return 409. |
| `POST /api/runs` | `chatId` plus message or attachments. Accepts `messageId`, model and params, reference text and agent ID. Returns `202 {job,queueMessage}`. 400 invalid input/chat, 403 restricted model, 409 active run or waiting for the user. The server deduplicates by message ID on enqueue. Compare with the web `/api/chat` path before enabling send across agent modes. |
| `GET /api/runs?chatId=…&jobId=…&events=1&stream=1&after=2` | SSE for persisted events with ID greater than `after`, scoped by chat, job and user. Run route reads the query cursor, unlike chat sync. Omitting `stream` returns `{events}`, omitting `events` returns `{jobs}`. `mode=snapshot` skips text/thinking deltas. |
| `GET /api/chats/events` | SSE using `Last-Event-ID` or `after`. Fresh connections receive `ready` with the latest cursor. Resume replays accessible `chat` events with `{chatId,kind,updatedAt}`. The server suggests retry at 1500 ms and sends heartbeats. Reload authorized chat state after an event. |
| `GET /api/chats/status?ids=…` | `{statuses:{…}}`, up to 100 IDs, 400 for excessive input. Missing or inaccessible IDs report `unavailable`. |
| `POST /api/chat/cancel`, `POST /api/chat/resume` | Cancel takes `chatId`, returns `{ok:true,status:"cancel-requested"}`, 404 for missing/inaccessible chat or absent active run. Resume accepts `chatId,jobId` and returns `{ok,jobId,status}`, 404 if absent or 409 for active or unsafe resume. Only interrupted runs with a safe agent marker qualify. |
| `POST /api/chat/approval` | `{approvalId,decision,version?}`, decision is `allow`, `allow-session` or `deny`. Success includes `ok,approvalId,jobId?,chatId,decision`. Invalid input 400, absent/already resolved or otherwise rejected approval 404. Require version and fresh authorized state in any future mobile action adapter. |
| `POST /api/chat/answer` | `{questionId,values,version?}`, with `answers` accepted as an alias. Validates question fields, 400 with possible `fieldErrors`, 404 for missing question, 409 for stale/unavailable form. Uses a deterministic transcript message ID. |
| `POST /api/file-uploads`, `GET/PUT/POST/DELETE /api/file-uploads/[id]` | Create with `{name,mimeType,size,purpose?}` and receive upload metadata at 201. PUT sends binary chunks with `Upload-Offset`, POST completes, GET checks progress, DELETE removes. Invalid input 400, unknown 404, offset/contention 409, unsupported voice type 415. Server chunk limit 8 MiB, existing browser uses 512 KiB for proxies. Up to 10 attached files, account limit defaults to 1 GiB. Existing stored chat assets use owner-checked `/api/uploads/[chatId]/[name]`. |
| `GET/POST/DELETE /api/voice/transcribe` | POST multipart with `file` or completed `uploadId`, optional context/settings, responds with `{job,transcript}`. GET/DELETE take `jobId`. Feature flags and provider availability apply. Size hard limit 250 MiB, duration configured up to 3600 seconds, MIME allowlist in `lib/shared-context.ts`. Invalid input 400, unavailable 404, size 413, MIME 415, provider failure 502. |
| `GET/PATCH/POST /api/notifications` | GET `?after=` returns `{notifications,cursor,hasMore,prefs,clients}`, max 100. Without a cursor it returns the latest cursor and an empty list. PATCH updates preferences. POST creates a record and returns `201 {notification,delivery}`. Existing remote delivery is for registered desktop clients. |
| `GET/POST /api/notifications/inbox` | Separate project notification inbox. POST accepts `{all:true}` or `{ids:[…]}` (max 100) for mark-read operations. |
| `GET /api/models`, `GET /api/projects?q=…` | Existing signed-in model catalog and owner/member project list. A new chat sends with the catalog's `defaultModelId` when it has no selected model. An agents-mode project loads `/api/projects/[id]/agents`. |

These routes require authentication unless listed otherwise. No route-local
request bucket was found on the read-only chat or run stream handlers. Reverse
proxy limits are deployment-specific. SQLite migration and account/session/job
schema ownership remain with [lib/sqlite.ts](../lib/sqlite.ts).

## Mobile capabilities and review

| Request | Contract |
| --- | --- |
| `GET /api/mobile/capabilities` | Signed-in response `{version:1,apns:boolean}`. |
| `GET /api/mobile/session` | Returns only the authenticated cookie owner's `username`. |
| `POST /api/mobile/session` | Register `{ticket}` against the authenticated cookie session. Ticket is 64 lowercase hex characters. SQLite stores only its hash and the linked session hash. |
| `DELETE /api/mobile/session` | Redeem `{ticket}` without the original cookie. Only revocation is allowed. Known, redeemed and unknown well-formed tickets have the same response. The app can erase login credentials immediately during offline logout. |
| `POST /api/mobile/devices` | `{installationId,token,topic,environment,events?}`. The server requires a live cookie session, validates the topic/environment, encrypts the token and binds the device to the owner and session. Event filters accept `done`, `error`, `question`, `approval`. 201, invalid 400, missing session 401, limit 409/429, unavailable 503. |
| `GET /api/mobile/devices` | Lists only the account's registered installations, their environment, expiry and event filters. Never returns APNs tokens or session identifiers. |
| `DELETE /api/mobile/devices` | `{installationId}` deletes the signed-in user's device and queued notifications. Session revocation also deletes both. |
| `GET /api/mobile/notifications/[id]` | Resolves an opaque push reference to `{chatId}` only for the same owner with current chat access. 401/404 otherwise. |
| `GET /api/mobile/approvals?chatId=…` | Returns the caller's pending approval and current version, or `{approval:null}`. The existing chat ACL and approval owner both apply. |
| `POST /api/mobile/approvals` | `{approvalId,version,decision}` with `allow` or `deny`. The existing resolver owns the atomic version transition. Missing/malformed version or session-wide decisions are rejected. |

## Run SSE fixture catalog

| Frame | Client interpretation |
| --- | --- |
| `id: 1\nevent: text\ndata: {"text":"Grüße 🌱","sequence":1}\n\n` | Persisted delta. Advance the cursor after consuming it. The fixture also sends a second delta and verifies replay with `after=1`. |
| `: heartbeat\n\n` | Transport keepalive after about 15 seconds of inactivity. No cursor advance. |
| `event: status\ndata: {"status":"reconnect","message":"Event stream window ended; reconnecting."}\n\n` | Reconnect from the last processed cursor. Server window defaults to 30 minutes. |
| `event: done\ndata: {"status":"completed"}\n\n` | Terminal fallback without an ID when job state is terminal and replay is drained. A stored terminal event can have an ID. |
| `event: error\ndata: {"message":"Agent run interrupted."}\n\n` | Terminal error fallback. Distinguish from HTTP or transport loss. |

The Swift smoke test covers multibyte text, cursor replay and a real
Metis worker run against a deterministic loopback provider. The UI reconciles
the final chat page after completion. Real external provider behavior and
network interruption on iPhone are separate acceptance checks.
