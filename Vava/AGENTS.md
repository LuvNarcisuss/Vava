# Vava iPhone project

- Read Docs/Product.md and Docs/Integration.md before editing behavior or configuration.
- Implement the iPhone application in Swift and UIKit, targeting iOS 16 or later. Keep protected persistence, AVFoundation, StoreKit 1 and nearby communication in the existing Swift services. Open Vava.xcodeproj for the configured StoreKit Run scheme.
- Use Vava for the app display name, project, app target, and shared scheme. Use `im.seex.sao2` and Yu Sun (`JPTS6M4T5B`) for Debug testing. Use `com.vava.pingpong` for Release. Keep personal activity in the protected app container and app resources under Assets.
- Keep five independent navigation roots in order: Academy, Watch, Shorts, Chats, Me. Open the first tab by default.
- Use English for project artifacts and app-owned text. Use original image-model raster glyphs and backgrounds and bundled OFL typefaces.
- Keep the runtime independent of the retired backend. Preserve publisher links and their original attribution.
- Preserve UUIDs, account isolation, original media, and atomic wallet persistence. Enable checkout only for verified catalog entries. Credit verified StoreKit transactions once before finishing.
- Compile, typecheck, launch, use Preview or Simulator, and run runtime tests only with explicit owner authorization.
- Use the iPhone 17 Pro simulator named exactly `Vava QA` for every simulator build, install, launch and test. Resolve its local UDID with `python3 Tests/qa_simulator.py` and use the same destination throughout the run. Report the simulator name and iOS version with the results.
