# Metis for iPhone

Open `MetisApple.xcodeproj`, select the shared **Metis** scheme and choose an
iPhone running iOS 17 or later. The scheme embeds the Share Extension and the
watchOS 8+ companion. For signed builds, follow the
[signing and provisioning steps](../../docs/APPSTORE-RELEASE-CHECKLIST.md).

Enter the canonical HTTPS origin of a configured Metis server, such as
`https://metis.example.com`, and sign in with an existing Metis account.
The app checks that the session can read the chat list before displaying it.
Create or open a chat, send a message, and watch the server stream. Use
**Stop** to cancel a run or **Load earlier messages** to read older pages.
The tab bar contains Chats, Activity, Projects and Settings. The chat filter
can show archived chats. Manage push and Watch access in Settings.
The app remembers the active server and restores a valid cookie
from the device Keychain after restart. Use the system keyboard microphone for dictation.

On a paired Watch, opt in under **Allow Apple Watch access** on the iPhone.
The Watch can list chats and pending requests, send short prompts after
confirmation, deny a current approval with server acknowledgement, and hand
off a chat to the iPhone. Review the full tool context and allow actions on
the iPhone.

Share links or text to Metis from the system share sheet, then open Metis to
review the draft. In a chat, use **Attach** to choose files, photos or camera
images. Metis uploads only when you tap **Send**.

## watchOS 8 compatibility

The Watch target declares `WATCHOS_DEPLOYMENT_TARGET = 8.0`. Its navigation
uses `NavigationView` and selection-based `NavigationLink`, and its change
handlers use the single-value `onChange` overload. The minimum is watchOS 8
because the UI uses SwiftUI `task` and confirmation dialogs. The Watch
continues to relay requests through an unlocked, signed-in iPhone with
**Allow Apple Watch access** enabled. It stores no server credentials.

Use the shared **MetisWatch** scheme for simulator builds. Check chat opening
and Back, creating a chat and opening it immediately, prompt confirmation,
retry after a lost connection, pending requests and confirmed denial. Disable
Watch access or sign out on the paired iPhone while a prompt is open: the
Watch must clear the old account's chats and return to the root. Watch
Simulator availability does not prove watchOS 8 runtime compatibility;
record the actual runtime and the built app's minimum OS separately.

Xcode 27.2 could not download the requested watchOS 8.3 arm64 simulator
runtime; the available watchOS 27.2 runtime is a separate current-OS check.
A toolchain/runtime that supports watchOS 8 is still needed for the legacy
runtime acceptance test. The committed/device target remains 8.0. For a
current Watch simulator, use the
[SDK-scoped invocation](../../docs/APPLE-CLIENTS-IMPLEMENTATION.md#building-with-a-newer-watch-simulator-sdk)
to derive its minimum from live SDK metadata and override only the simulator
build. Xcode 27.2's SDK requires 9.0 for a full build; Apple's matrix lists
watchOS 8 deployment support in Xcode 26.6. A successful source typecheck at
8.0 does not make a 9.0-minimum simulator artifact an 8.0 runtime test.

## Native appearance

The iPhone views use the current Metis web app's flat neutral palette, compact
controls and original vector wordmark. Light and dark appearance follow the
device. The sign-in screen uses labeled fields, chats show their server and
available activity metadata, and the conversation keeps assistant text open
with muted user bubbles and a bordered composer. The model menu sits beside
the attachment control; available models still come from the server.

Design references: `app/globals.css`, `components/app-shell.tsx`,
`components/composer-add-menu.tsx`, and `public/metis-wordmark.svg` in
[the official repository](https://github.com/f1shyondrugs/metis), reviewed at
`7d3bf21562244ed3596b5bba9c3bea7dee34885d`. The asset catalog retains the
wordmark's paths and proportions and renders it as a light/dark template.

The November native design changes were prepared on the Linux development
server with native Mac validation deferred. Xcode compilation, updated simulator
screenshots, Dynamic Type/landscape checks, VoiceOver and signed iPhone
installation still need to run on the Mac. The UI suite includes screenshot
attachments and a sign-in keyboard/accessibility layout check for that pass.
The earlier verification results describe the preceding native build.

## Personal Team iPhone test

For a free Personal Team, prepare a separate iPhone-only project on the Mac:

```sh
python3 clients/apple/scripts/prepare-personal-team.py \
  --team '<TEAM_ID_FROM_XCODE>' \
  --bundle-id '<YOUR_UNIQUE_BUNDLE_ID>' \
  --output /tmp/metis-personal-team-test
```

Use your own Team ID from Xcode Settings → Accounts and an available bundle ID.
The output directory must be new and outside the checkout. The helper creates
`MetisPersonalTeam.xcodeproj` with the shared **Metis Test** scheme and display
name. Open that generated project, select the connected iPhone and run with
your authenticated Personal Team. Preparation does not build, provision or
install anything; the original project and schemes stay unchanged.
Regenerate the temporary project if its directory or the source checkout moves.

This variant omits Push entitlements, App Groups, the Share Extension and Watch
companion. Push alerts, share-sheet handoff and the Watch app are unavailable.
Chat, attachments and the existing HTTPS/Keychain session behavior remain in
the iPhone sources. No Watch Simulator runtime download is needed.

## Local fixture

From the repository root, install the repository dependencies and start the
fixture in one terminal:

```sh
pnpm install --frozen-lockfile
node --import tsx clients/apple/Tests/fixture-server.ts
```

The fixture binds only to IPv4 loopback on port 43100 and uses a fresh temporary
database. It routes HTTP requests to the real Metis handlers and supplies
synthetic data and replay events. The live-run test uses the real submission
and agent workers plus the built-in MCP tool catalog. Its compatible model
provider is a deterministic HTTP fixture on the same loopback listener.
Run the fixture as your normal non-root Mac user.
Stop it with Ctrl-C.

Use `http://localhost:43100` in a **Debug iPhone Simulator** build with
`metis-apple-fixture-alice` / `apple-fixture-only`. These are public fixture
credentials, never use them for a real account. Physical devices and Release
builds require HTTPS.

To run the API smoke test on the Mac while the fixture is running:

```sh
swiftc -D DEBUG clients/apple/MetisiOS/MetisAPI.swift clients/apple/Tests/Smoke.swift -o /tmp/metis-apple-smoke
/tmp/metis-apple-smoke
```

The smoke test changes chats, messages and run state. Before running the UI
tests, stop only the fixture with Ctrl-C in its terminal and start it again:

```sh
node --import tsx clients/apple/Tests/fixture-server.ts
```

Each restart creates a fresh temporary database with the original seed.
Restart between smoke and UI test runs so the suites do not share mutated data.
With an installed iPhone Simulator runtime and the fresh fixture running,
run the native UI tests:

```sh
xcodebuild -project clients/apple/MetisApple.xcodeproj -scheme Metis \
  -destination 'platform=iOS Simulator,name=<installed iPhone>' \
  -parallel-testing-enabled NO test
```

Keep normal simulator code signing enabled for UI tests so Keychain session
restoration can be exercised. Simulator signing does not require an Apple
Developer team. The commands below disable signing for compilation checks.

To compile without code signing:

```sh
xcodebuild -project clients/apple/MetisApple.xcodeproj -scheme Metis \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project clients/apple/MetisApple.xcodeproj -scheme Metis \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

See the [implementation notes](../../docs/APPLE-CLIENTS-IMPLEMENTATION.md)
for the tested scope and device requirements.
