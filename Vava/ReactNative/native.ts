import {
  NativeEventEmitter,
  NativeModules,
  requireNativeComponent,
  ViewProps,
  NativeSyntheticEvent,
} from "react-native";

import type { Response, Snapshot } from "./contracts";
export * from "./contracts";
const module = NativeModules.VavaNative;
export function request(
  command: string,
  payload: Record<string, unknown> = {},
): Promise<Response> {
  return module.request(command, payload);
}
export function subscribe(listener: (snapshot: Snapshot) => void): () => void {
  const subscription = new NativeEventEmitter(module).addListener(
    "stateChanged",
    listener,
  );
  return () => subscription.remove();
}
export const NativeVideo = requireNativeComponent<
  ViewProps & {
    uri: string;
    poster?: string;
    paused: boolean;
    seekFraction?: number;
    onProgress?: (
      event: NativeSyntheticEvent<{ currentTime: number; duration: number }>,
    ) => void;
    onError?: (event: NativeSyntheticEvent<{ message: string }>) => void;
  }
>("VavaVideo");
export const NativeCallVideo =
  requireNativeComponent<ViewProps>("VavaCallVideo");

// Every command returns a fresh snapshot after a successful operation.
// bootstrap, refresh, login {accepted}, signOut, deleteAccount
// activity {id, kind: like|save|hide, enabled}, report {id, reason}
// follow/block {id, enabled}, practice {id, step, completed}, unlock {id}
// editProfile {name,bio,avatarURI?}, pickAvatar (returns avatarURI without saving), importVideo {title,accepted}, removeVideo {id}
// comment {clip,body,replyTo?}, share {id?,url?,text?}, openURL {url}
// walletRefresh, buy {productID,price}, retryPurchases
// chatStart, chatOpen/chatClose/chatHide {id}, chatInbox {id,pinned?,unread?}
// chatFollow/chatBlock {id,enabled}, chatSend {id,text,retryID?}
// chatCall {id,video}, callAnswer/callEnd {id}, callMute {muted}
