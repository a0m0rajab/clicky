# Clicky for iPhone and iPad

A community SwiftUI client for the open-source Clicky backend. Requires iOS 17+
and Xcode 15+. This is not the official HeyClicky app, and does not change the
existing macOS app or Worker.

## Run

1. Open `mobile/ClickyMobile.xcodeproj` in Xcode.
2. Select the **ClickyMobile** scheme and an iPhone/iPad simulator or device.
3. In Signing & Capabilities, select your team and a unique bundle identifier
   instead of the placeholder `com.example.clicky.mobile`.
4. Run with **Cmd + R**. Follow the repository's policy: do not run `xcodebuild`
   from the terminal.
5. Open the app's Settings and enter the **HTTPS base URL of a Worker you own**,
   without `/chat` or `/tts`. Deploy the existing `worker/` using the root README.
   The app does not use the original author's deployed service.

The existing Worker needs `ANTHROPIC_API_KEY` for chat. Enable **Speak replies**
only after configuring `ELEVENLABS_API_KEY` and `ELEVENLABS_VOICE_ID`. Apple Speech
handles mobile dictation, so this client does not need AssemblyAI. Provider keys
belong only in Cloudflare secrets; never put them in the iOS app.

## Use

- Type a question or choose one of the starter prompts.
- Tap **+** to select a screenshot or photo through the system picker. Images are
  resized to a maximum 1568-pixel edge and encoded as JPEG before sending.
- Tap the microphone, dictate, tap again to stop, review the text, then send.
  Permissions are requested only when you use dictation. Speech recognition
  availability varies by locale/device; typed chat always remains available.
- Responses stream into the conversation through the Worker's existing `/chat`
  endpoint. Optional spoken replies use `/tts`.
- Start a new conversation with the top-left button. No conversation is written
  to disk. Your Worker URL and voice preference are stored locally.

## Privacy and platform limits

Only explicitly selected images are shared with the configured Worker and its AI
provider. Dictation may send audio to Apple's speech recognition service.
Microphone capture, response requests, and playback stop when the app becomes
inactive. iOS does not support Clicky's macOS global cursor overlay, global
push-to-talk shortcut, or unrestricted background screenshots. This client does
not implement live screen broadcasting, a share extension, Android, or App Store
distribution.

Use a private, access-controlled Worker before distributing this client. The
upstream proxy has no application authentication or abuse controls; this addition
does not change that. A public Worker URL can incur charges if others discover it.
No production credentials, endpoint, signing team, or paid deployment is bundled.

## Validation

Run `python3 mobile/check_project.py` for portable Info.plist, permission, source
membership, project-reference, and shared-scheme checks. These checks do not
compile Swift or verify native runtime behavior.

The native app must be built and exercised in Xcode; a Linux sandbox cannot
validate SwiftUI/UIKit compilation or capture a running iOS preview. No native
build or live provider success is claimed without that verification.

Device acceptance checklist:

1. Build and run on an iOS 17+ simulator, then a physical iPhone.
2. With no Worker URL, Send shows configuration guidance without discarding input.
3. Configure your Worker; send two questions and check streamed text and context.
4. Attach a screenshot, remove it, reattach it, then ask about its contents.
5. Deny microphone/speech permissions; verify the error and typed-chat fallback.
6. Allow permissions; start/stop dictation repeatedly and verify editable text.
7. Enable spoken replies; check audio, then check typed replies with TTS unavailable.
8. Background during dictation and streaming; verify recording stops and the UI
   recovers. Test network loss and invalid Worker URLs without exposing raw errors.
9. Check portrait/landscape on iPad, Dynamic Type, and VoiceOver labels.

An app icon, signing, privacy disclosures, native testing, and authenticated
backend access are still needed before a production/App Store release.
