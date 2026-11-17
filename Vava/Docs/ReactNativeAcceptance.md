# React Native simulator acceptance

Date: November 16, 2026. Scope: the owner-authorized build, launch and functional review of the migrated interface.

## Environment

- Workspace and scheme: `Vava.xcworkspace`, `Vava`, Debug.
- Build tools: Xcode 26.0.1 (17A400), React Native 0.85.3, React 19.2.3.
- Device: Vava UI Acceptance, iPhone 17 Pro, iOS 26.0.
- Simulator UUID: `C6BBDAF1-EF03-4F2E-980F-CB8C472367D6`.
- Debug application: `im.seex.sao2`, installed from the current workspace build.
- JavaScript: the current workspace served by Metro on port 8081.

## Results

| Area | Observed result |
| --- | --- |
| Build and startup | TypeScript checking and the Debug workspace build pass. Current app installs and cold-starts. The final cold-start console has no application warning or exception. |
| Academy | Cards and course detail render; search narrows results; Free price filtering shows the free course; save/remove and practice complete/reset update the native snapshot. |
| Publisher | Credited profile and tutorials render. Follow/unfollow updates the count and restores the prior state. |
| Watch | Replay list and detail render; save/remove works. The original YouTube URL opens in the native browser sheet. External playback was not established. |
| Shorts | Bundled footage plays, pauses and resumes. Like/unlike updates counts. Up/down swipes change the selected clip. Progress updates. The comments sheet renders over continuing footage; reply/cancel controls work. |
| Chats | Empty inbox and Find players screen render. Discovery shows the local player code and searching state without fabricating peers. |
| Me | Existing profile and wallet restore. Collection taps and horizontal swipes switch collections; the learning empty state renders. |
| Settings | Profile editing saves and reloads the changed name; the original name was restored. Blocked publishers and media credits render. |
| Native media | The system profile-photo picker loads and cancels back to an enabled edit form. The video import form renders and prevents submission with missing input. |
| Wallet | Nine localized local StoreKit offers load. Selecting a pack enables checkout. The Xcode test purchase sheet opens. Canceling displays Purchase canceled and preserves the balance and existing entries. |

## Fixes verified during this run

- Override inherited Jest ambient types with the application React and React Native types.
- Construct native video views with an explicit frame initializer.
- Link libc++ in both the project source and generated Xcode target.
- Allow React Native to control the status bar through Info.plist.
- Replace the deprecated core SafeAreaView with safe-area-context and its provider.
- Recognize vertical Shorts swipes from touch endpoints, keep them separate from taps, and support coalesced movement events.
- Handle horizontal collection swipes in the Me content area, including coalesced movement events.
- Give unloaded video progress a nonzero accessibility range.

## Data preservation

Existing library and local wallet JSON files were backed up before installing the migration. A final semantic comparison found the local wallet unchanged. The profile, likes, saves and following state were restored after reversible checks. Discovery initialized the protected chat identity. Completing and resetting the free drill left an empty progress entry; no completed drill remains. No existing account, work, transaction or private message was deleted. No new private comment, outgoing message or completed purchase was created.

## Remaining coverage

This is a manual simulator acceptance pass, not exhaustive service validation. Two physical iPhones are required for mutual follows, acknowledged message delivery, call audio/video, and connection-loss handling. No Apple sandbox or production purchase was made. The subsequent [isolated wallet acceptance](WalletStoreKitAcceptance.md) covers successful local purchase delivery, cancellation and duplicate-callback idempotency. Deferred approval and verification/storage failures remain pending; the historical UIKit feedback harness has not been revalidated against the React Native accessibility tree. Video import completion, photo selection/save, comments persistence, report/hide mutations, account deletion and large accessibility text sizes were not exercised in this pass. External sites depend on network availability.

## Reproduction

With execution authorized, run Metro using `npm start`, then build the workspace:

```sh
xcodebuild -workspace Vava.xcworkspace -scheme Vava -configuration Debug \
  -destination 'platform=iOS Simulator,id=C6BBDAF1-EF03-4F2E-980F-CB8C472367D6' \
  -derivedDataPath /tmp/vava-rn-acceptance build CODE_SIGNING_ALLOWED=NO
```

Install `Build/Products/Debug-iphonesimulator/Vava.app` from that derived-data directory and launch `im.seex.sao2` on the same simulator. StoreKit local offers in this session came from the existing Xcode test environment; a fresh simulator should be launched with the scheme's StoreKit configuration to establish that environment. Build output for this run is at `/tmp/vava-rn-build.log`; Metro output is at `/tmp/vava-metro.log`. Temporary logs are not repository artifacts.
