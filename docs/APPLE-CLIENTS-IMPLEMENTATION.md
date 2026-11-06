# Apple clients implementation

## First delivery

Branch `feat/apple-clients`, based on upstream `master` at
`a5a70d4bbcb56c9a8cf582d37e3a7467840d35ce`. The remote HEAD matched the plan.
The Apple clients use the existing TypeScript handlers and SQLite data as the
source of truth. The Xcode project contains the iPhone app, Watch companion,
and iPhone Share Extension. The server adds an optional APNs device registry,
outbox and versioned mobile approval routes. See the
[API inventory](./APPLE-API-INVENTORY.md).

| Milestone | Evidence and remaining scope |
| --- | --- |
| A, audit and spikes | Pinned source, API inventory, SSE replay and a live Metis worker stream against a deterministic local provider verified. Signed device launch and Series 3 hardware testing remain open. |
| B, connection | Login, logout, active server selection and expired-session handling. The latest valid cookie is restored through device-only Keychain storage. Offline logout erases login credentials and queues a revocation-only ticket. |
| C, chats | List, search, pin, archive, paginated history, create/send, live SSE, resume cursor and cancel. Chat rows refresh by ID during live sync and the visible history uses HTTP validators. The transcript has Markdown, code copying and expandable tool activity and reasoning previews. |
| D, Push | Owner-scoped encrypted registration, durable outbox, APNs HTTP/2 delivery and notification routing. Stubbed delivery tests cover retry and revocation. Signed APNs delivery still needs a test device. |
| E, decisions | Native approval review with biometric confirmation, versioned server-side resolution and question forms. Allow and question answers require the phone app. |
| F, iPhone features | Chats, Activity, Projects and Settings tabs. The Activity badge counts chats with pending decisions. Model catalog, project agents, system dictation, attachments, account and device settings, and redacted diagnostics. Main controls have German translations. |
| G, Watch | watchOS 10+ companion with opt-in phone relay, chat status, new chats, short prompts, pending questions and approvals, confirmed denial and iPhone handoff. Pairing, dictation, foreground/background behavior and mirrored notifications require testing on hardware. |
| H, device integrations | File/photo/camera selection, Shortcuts with a draft preview, and Share Extension for text and links. App Group provisioning and device tests remain open. |
| I, release | Reproducible unsigned builds, app icons, a privacy manifest, local tests, CI configuration, and a [release checklist](./APPSTORE-RELEASE-CHECKLIST.md). Signing, store screenshots, review demo, TestFlight and external acceptance remain open. |

## Foreground chat follow-up — 6 November 2026

The previous uncommitted Apple implementation is preserved in baseline commit
`cc70add` on branch `feat/apple-foreground-sync`. The follow-up changes are
separate from that snapshot.

- Chat-sync batches now invalidate the open transcript when its chat changes
  or the stream requests a full snapshot. An unrelated chat event does not
  reload the visible conversation. The detail view coalesces refreshes, waits
  for in-flight history loads and cancels its refresh task outside the foreground.
  The existing history window, run cursor, streamed text and composer binding
  remain in place.
- Sending validates an explicit or persisted model ID against the current
  server catalog before uploading attachments. A removed selection produces
  an English/German error and retains the draft. An unset selection uses only
  an available default returned by the server. Explicit server-provided legacy
  aliases resolve to their canonical account model only when the match is unique;
  an exact model ID takes precedence.
- Automatic refreshes retain send errors and the stable submission ID for a
  manual retry after a lost acknowledgement, including attachment-only messages.
- The fixture can append an external message through its loopback-only test
  control. The iPhone regression test requires that message to appear without
  navigation or a foreground switch and checks that the unsent draft survives.
  The same test failed on the previous transcript implementation at that assertion.
  CI now restarts its own fixture between Swift smoke and UI suites to avoid
  sharing mutated seed data. UI tests use normal simulator ad-hoc signing for
  Keychain access; unsigned compilation alone does not exercise session restoration.
- The development plan's status now points here instead of claiming that no
  implementation exists. Signing, APNs device delivery and Watch hardware
  acceptance remain open. Watch simulator/runtime downloads are deferred by
  operator instruction.

### Follow-up verification

On the existing Mac toolchain (Xcode 27.2, iOS 27.2 simulator, Node 26.3.0):

- Both iPhone UI tests passed: external foreground changes, preserved drafts,
  history pagination, lost-acknowledgement retry without duplicates, live worker
  streaming, background resume, Keychain relaunch, offline recovery and session
  revocation. The UI suite used simulator ad-hoc signing without a developer team.
- The final Swift smoke binary passed against a fresh isolated fixture, including
  live explicit/default model selection, rejection of a missing model, and
  server-advertised legacy alias resolution. It also exercised auth/isolation,
  history, replay, attachments and a real local worker stream.
- The focused backend command
  `node --import tsx --test tests/mobile-apple.test.ts tests/chat-submit-worker.test.ts tests/run-event-stream.test.ts`
  passed all 10 tests. The inherited revocation fixture now creates its isolated
  job through `enqueueJob` before appending events, satisfying the existing foreign key.
- The unsigned generic iPhone Release build (including Watch and Share Extension),
  TypeScript check, focused ESLint and Apple CI shell syntax checks passed.
  `NEXT_DIST_DIR=tmp/metis-apple-foreground-web-build pnpm build` passed with an
  isolated data directory. Generated temporary TypeScript paths were removed.
- `pnpm test` completed the backlog/provider groups (80/80 and 52/52) and the shared
  group (1,138 passed, 2 failed, 1 skipped). It stopped at that group's nonzero
  exit, so later chained groups were not reached. Both failures reproduced in a
  separate unchanged `cc70add` worktree: server-monitor startup reads a missing
  temporary `server-metrics.json`; workspace glob search compares macOS
  `/private/var/...` with `/var/...`. These remain pre-existing Web test issues.

No Watch runtime was installed or downloaded. No production deployment,
TestFlight upload, signed device/APNs delivery or physical Watch test was performed.

## Session and transport

Deployment target is iOS 17. The prototype bundle ID is a local build default.
Each login attempt owns an ephemeral URLSession. The app keeps only the active
session cookie and its exact origin in a device-only Keychain item, accessible
while the device is unlocked. Passwords are never stored. A restored cookie is
used only after an authenticated GET succeeds. A 401 clears local chat state.
Logout immediately erases the login cookie. On the next reachable foreground
contact, the app redeems a separately scoped revocation ticket if server
logout could not be confirmed. The ticket cannot read or create account data.
Unsent text stays in the current account's in-memory composer across chat
navigation. A retry of the same draft keeps its message ID. Logout and app
termination clear these drafts.

The iPhone closes both live streams outside the foreground. On activation it
refreshes the chat list and open transcript before reconnecting. A run that
remained open in memory resumes from its last processed event ID. The iPhone
simulator verified that switching away mid-response and returning resumes
from a nonzero cursor and displays the complete response.

Server origins must be HTTPS with normal system trust. Subpaths, credentials in
the URL, query strings, fragments and redirects are rejected. Only Debug on the
simulator and the Mac smoke binary accept HTTP on `localhost`. The Release
device bundle has no ATS exception. The local-network usage description covers
connections to a self-hosted instance on the LAN. A real deployment needs a
certificate trusted by the device and a route to the server, such as a VPN.

## APNs registration and review policy

The iPhone requests permission from the account menu. Device registration is
bound to the session owner and configured APNs topic/environment. Tokens are
encrypted with AES-256-GCM. Registrations expire with their session.
The server removes devices on session revocation, explicit deregistration and
permanent token rejection. Event filters apply per installation. The existing
observer dispatches a bounded outbox without coupling
push failures to the feed. See Apple's
[server setup](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)
and [device registration](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns).

Lock-screen payloads are generic and include only an opaque reference for
authenticated retrieval. The notification's Open Metis action requires device
authentication and opens the current server state. A Watch denial requires
confirmation and an online iPhone relay that verifies the latest approval ID
and version. The Watch
displays success after the server accepts the denial. The phone loads the
current tool context and checks biometrics for Allow.
The server requires the current approval version and uses the existing
atomic transition. Biometrics are a phone UI control. They do not prove
device authentication to the server. A stale/repeated decision is rejected.

## Apple Watch Series 3 gate

Apple lists Series 3 through watchOS 8.8.1. Installed Xcode 27.2 supports
deployment targets from watchOS 9. Xcode 26.6 lists watchOS 8 deployment and
the watchOS 26.5 SDK. As of 5 November 2026, Apple lists Xcode 26 and the
watchOS 26 SDK as the minimum for App Store Connect uploads. Therefore Xcode
26.6 is a candidate for a legacy spike, subject to installation, signing,
actual pairing and a successful archive/upload validation. Xcode 27.2 cannot
validate a watchOS 8 release. No legacy toolchain or paired Series 3 was tested.
Sources: [Apple Watch compatibility](https://support.apple.com/en-us/118490),
[Xcode requirements](https://developer.apple.com/xcode/system-requirements/),
[App Store Connect requirements](https://developer.apple.com/news/upcoming-requirements/).

Keep native Series 3 support provisional. If the legacy gate fails, use a
modern Watch target and test iPhone notification mirroring on a paired
Series 3 as the fallback. Mirroring depends on the phone/watch lock state and
notification settings. It provides alerts with platform-controlled behavior,
without promising the native Watch experience. [Apple Watch notification routing](https://support.apple.com/en-us/108369).

## Verification and handoff

- Xcode 27.2 compiled Debug for the iPhone 17 simulator and archived unsigned
  Release for generic iPhone. The archive contained the iPhone app, Watch app,
  Share Extension and privacy manifest. Release had no ATS exception.
- Native Foundation smoke test passed on macOS against the real Metis
  handlers with isolated SQLite. It covered credentials, two-account
  isolation, pagination, conditional HTTP 304, logout, replay, idempotency, cancellation, chunked
  upload and byte-exact download. It also ran the real Metis worker against a
  deterministic loopback provider, verified that the first response chunk
  arrived before completion, and compared streamed text with the saved
  assistant message. No external provider was called.
- The iPhone 17 simulator on iOS 27.2 passed the transport policy and
  sign-in/chat tests. The tests sent a prompt through the SwiftUI interface
  and the real Metis worker, displayed the fixture response and restored the
  Keychain session on relaunch. They also opened the Activity, Projects and
  Settings tabs, read the authenticated account name and returned to Chats.
- With the test server unreachable at launch, the iPhone kept the saved
  session and restored it after a manual retry. After server-side revocation,
  it returned to sign-in, hid chats and stayed signed out after relaunch.
- The chat fixture contains 75 messages. The Swift test loads all pages and
  checks for gaps or duplicates after a refresh. The iPhone test scrolls to
  the first message before sending and again after the live response.
- A delayed transcript request verified that the complete streamed text stays
  visible until the saved assistant message arrives.
- The fixture truncated the HTTP acknowledgement after committing a prompt.
  The iPhone kept the draft and displayed one user message after a manual
  retry. The Swift API test confirmed that both attempts used the same
  committed job and that only one message was stored.
- A two-account HTTP probe verified that an ID-filtered chat-list response
  returns only requested and accessible chats, rejects empty IDs and requires
  authentication.
- Backend tests covered durable delivery, account isolation, approval races,
  Web submission idempotency and SSE replay. The focused suite passed 32
  tests, including a loopback HTTP/2 check of the APNs request, ES256
  signature, and redacted payload. This check did not contact Apple.
  The full Web suite also ran. Its two failures, the server-monitor
  startup sample and the macOS temporary-path comparison in workspace search,
  reproduced on the unchanged upstream baseline. The Next.js production build
  and TypeScript checks passed. Targeted lint passed. Repository-wide lint
  reported 39 errors and 18 warnings in unchanged files. Reproduction
  instructions are in the
  [client README](../clients/apple/README.md).
- Device gate: choose a signing team and available bundle ID, install on an
  iPhone, then check trusted HTTPS, local network permissions, login, history,
  logout and session expiry against an isolated Metis instance.
- Next acceptance steps: sign a development build, run the device matrix,
  then validate the release archive and APNs sandbox/production configuration.
