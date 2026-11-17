import type { Response, Snapshot } from "../ReactNative/contracts";

declare global {
  interface Window {
    webkit?: {
      messageHandlers: { vava: { postMessage: (message: unknown) => void } };
    };
  }
}
let sequence = 0;
const page = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
const pending = new Map<
  string,
  { resolve: (value: Response) => void; reject: (error: Error) => void }
>();
const listeners = new Set<(snapshot: Snapshot) => void>();
window.addEventListener("vava-native", ((event: CustomEvent) => {
  const message = event.detail;
  if (message.type === "snapshot")
    listeners.forEach((listener) => listener(message.snapshot));
  if (message.type === "response") {
    const operation = pending.get(message.id);
    if (!operation) return;
    pending.delete(message.id);
    if (message.error) operation.reject(new Error(message.error));
    else operation.resolve(message.result);
  }
}) as EventListener);
export function request(
  command: string,
  payload: Record<string, unknown> = {},
): Promise<Response> {
  return new Promise((resolve, reject) => {
    const handler = window.webkit?.messageHandlers.vava;
    if (!handler) {
      reject(new Error("Open Vava to use this page."));
      return;
    }
    const id = `web-${++sequence}`;
    pending.set(id, { resolve, reject });
    handler.postMessage({ id, page, command, payload });
  });
}
export function subscribe(listener: (snapshot: Snapshot) => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}
