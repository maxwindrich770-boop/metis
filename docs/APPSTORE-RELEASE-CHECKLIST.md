# Apple device testing and release

## Configure a signed test build

1. In Apple Developer, register the iPhone bundle ID, its `.watchkitapp`
   companion ID and the `.share` extension ID. Replace the prototype value
   with the same `METIS_PHONE_BUNDLE_ID` across the Xcode targets.
2. Enable Push Notifications for the iPhone target. Enable the App Group
   `group.<iPhone bundle ID>` for the iPhone and Share Extension. Choose the
   same signing team for all three targets.
3. Use an isolated Metis server and test accounts with trusted HTTPS. Enable
   APNs with `METIS_APNS_TOPIC`, `METIS_APNS_TEAM_ID`, `METIS_APNS_KEY_ID`,
   `METIS_APNS_KEY_PATH`, `METIS_APNS_TOKEN_KEY` and
   `METIS_APNS_ENVIRONMENT`. Keep the private key and independent 32-byte
   hex encryption key outside Git and the app. Debug uses sandbox, Release
   uses production. Rotating the encryption key requires device re-registration.
4. Install on a real iPhone and pair a Watch. For the production APNs test,
   install a signed TestFlight build against an isolated production APNs setup.

## Acceptance on hardware

- Sign in, switch accounts and servers, sign out while offline, and revoke an
  active session. Verify chat and push isolation across these transitions.
- Use a real provider account on the isolated server. Create a chat on each
  client and verify it appears on the other. Stream a response, interrupt
  connectivity, reconnect, send once, and cancel an active run. Verify a
  resumed run does not replay a terminal event from the interrupted attempt.
- Receive completion, error, question and approval alerts with the phone
  locked and the app closed. Check disabled notification permission, device
  deregistration, push taps after expiry, and generic lock-screen content.
- Compare approval/version state with the web app. Verify wrong account,
  stale version, concurrent decisions and denied/cancelled Face ID. Test
  typed question fields, custom options, validation and expiry.
- Use a Watch to send a dictated prompt and receive server acknowledgement.
  Check Bluetooth loss, phone locked, Watch restart and account switching.
  Test Series 3 notification mirroring separately.
- Test camera/photo/file selection, multi-chunk upload, secure attachment
  opening, share-group handoff, and Shortcuts draft preview. Check VoiceOver,
  larger text, low memory, very long messages, and poor connectivity.

## Store handoff

- [ ] Validate a signed archive containing the Watch app and Share Extension.
- [ ] Verify the included Metis icons in the signed archive and supply
      screenshots, support URL, and accessibility metadata.
- [ ] Publish an operator-specific privacy policy. Report the data actually
      collected, including account identifiers, chat content, attachments,
      device tokens, and any diagnostics used in the distribution build.
      Self-hosted server operators and connected model providers may process
      this data. Camera/photos/files are user-selected. APNs gets generic
      notification content and an opaque reference.
- [ ] Create an isolated, reachable HTTPS review demo with fictional content.
      Provide login instructions and a safe model/provider configuration.
      Supply a guided review flow for chat, push, approval and Watch handoff.
- [ ] Verify current [Apple submission requirements](https://developer.apple.com/news/upcoming-requirements/)
      and [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
- [ ] Run TestFlight and review crashes, accessibility and privacy behavior.
- [ ] Obtain explicit release authorization before submitting publicly.

## Draft App Store description

Metis brings your self-hosted Metis workspace to iPhone and Apple Watch.
Connect to your server to pick up existing chats, send messages, stream
responses, attach files and review requests from agents. The Watch companion
can show chat status and send short prompts through your iPhone.

Requires access to a compatible Metis server over trusted HTTPS. Model
availability depends on the providers configured on that server. Push requires
the server's Apple Push Notification service configuration.

## Review demo runbook

1. Prepare a separate HTTPS Metis instance running the release candidate.
   Use an isolated data directory and a non-admin review account with an
   execution workspace provisioned by the normal Metis setup flow.
2. Seed a sample chat with fictional content. Configure a review model
   credential with bounded usage and a mode scoped to the demo workspace.
   Keep any real projects, accounts, or remote clients out of the instance.
3. Provide the demo origin and account credentials through App Store Connect's
   review information. Include steps to open the sample chat, send a prompt,
   attach a file, and navigate to the activity inbox. Show the opt-in Watch
   setting, confirmed denial on the Watch and full approval review on the
   iPhone.
4. Test the supplied instructions with a fresh device before submission.
   The local fixture in this repository is for development only and uses
   public credentials on loopback.
