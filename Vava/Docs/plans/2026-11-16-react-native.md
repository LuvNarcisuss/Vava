# React Native migration implementation plan

## Approved scope

The owner selected a complete React Native interface migration with native modules for payments, media and nearby communication. React Native and TypeScript become the default for future apps. Existing Vava behavior is specified in Product.md and Integration.md.

## Architecture

Use the existing iOS host with React Native and TypeScript. Retain LocalLibrary, Wallet, ChatService, ChatTransport and ChatMedia as authoritative native services. Expose one asynchronous command interface and a state snapshot to React Native. Keep the account and wallet files, stable IDs, signing identity, five navigation roots and original artwork. Replace UIKit product screens with React Native routes. Native picker, sharing, browser and media surfaces remain platform components.

## Implementation

- [x] Expose native services through VavaNative, including bootstrap, consent, persistence, catalog, wallet, content actions, imports and nearby messages and calls.
- [x] Implement TypeScript application state and Academy, Watch, Shorts, Me, Settings, Wallet, profiles and discussion routes with the existing theme.
- [x] Implement Chats, player discovery, conversation and call interfaces against the same native service contract.
- [x] Wire the React Native entrypoint, iOS lifecycle, dependencies, Metro, CocoaPods and release bundling into the existing project generator.
- [x] Review source contracts, routes, asset references, account isolation and project configuration. Update the project rules and delivery evidence.

## Verification boundary

The owner has authorized migration and static inspection. Compilation, typechecking, Metro execution, application launch and runtime tests require separate explicit authorization. Pending runtime acceptance includes all routes on Vava UI Acceptance, persisted upgrade data, StoreKit delivery and two-device nearby communication.
