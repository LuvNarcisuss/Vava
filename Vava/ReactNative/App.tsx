import React, { useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  Image,
  NativeSyntheticEvent,
  Pressable,
  requireNativeComponent,
  StatusBar,
  StyleSheet,
  Text,
  View,
  ViewProps,
} from "react-native";
import { request, subscribe } from "./native";
import { ScreenBackground } from "./ScreenBackground";

const commands = new Set([
  "bootstrap",
  "refresh",
  "login",
  "signOut",
  "deleteAccount",
  "activity",
  "report",
  "follow",
  "block",
  "practice",
  "unlock",
  "editProfile",
  "pickAvatar",
  "importVideo",
  "removeVideo",
  "comment",
  "share",
  "openURL",
  "walletRefresh",
  "buy",
  "retryPurchases",
  "chatStart",
  "chatOpen",
  "chatClose",
  "chatHide",
  "chatInbox",
  "chatFollow",
  "chatBlock",
  "chatSend",
  "chatCall",
  "callAnswer",
  "callEnd",
  "callMute",
  "callPreviewStart",
  "callPreviewStop",
]);
const LocalPage = requireNativeComponent<
  ViewProps & {
    messages: string;
    onDelivered: (event: NativeSyntheticEvent<{ id: number }>) => void;
    onMessage: (event: NativeSyntheticEvent<{ body: string }>) => void;
    onFailure: (event: NativeSyntheticEvent<{ message: string }>) => void;
  }
>("VavaLocalWebView");

export default function App() {
  const delivery = useRef(0);
  const [outbox, setOutbox] = useState<{ id: number; body: string }[]>([]);
  const active = useRef(true);
  const ready = useRef(false);
  const highestID = useRef(0);
  const pageID = useRef("");
  const generation = useRef(0);
  const [failure, setFailure] = useState("");
  const [loading, setLoading] = useState(true);
  const [attempt, setAttempt] = useState(0);
  function send(message: unknown) {
    if (!active.current) return;
    const item = { id: ++delivery.current, body: JSON.stringify(message) };
    setOutbox((previous) => [...previous, item]);
  }
  useEffect(() => {
    active.current = true;
    const unsubscribe = subscribe((snapshot) => {
      if (ready.current) send({ type: "snapshot", snapshot });
    });
    return () => {
      active.current = false;
      unsubscribe();
    };
  }, []);
  async function receive(event: NativeSyntheticEvent<{ body: string }>) {
    let message: {
      page: string;
      id: string;
      command: string;
      payload: Record<string, unknown>;
    };
    try {
      message = JSON.parse(event.nativeEvent.body);
      if (
        !/^web-[1-9][0-9]*$/.test(message.id) ||
        !commands.has(message.command) ||
        !message.payload ||
        Array.isArray(message.payload) ||
        typeof message.payload !== "object"
      )
        throw new Error();
      if (typeof message.page !== "string" || message.page.length > 80) return;
      if (message.page !== pageID.current) {
        if (message.command !== "bootstrap") return;
        pageID.current = message.page;
        highestID.current = 0;
        generation.current += 1;
      }
      const id = Number(message.id.slice(4));
      if (!Number.isSafeInteger(id) || id <= highestID.current) return;
      highestID.current = id;
    } catch {
      return;
    }
    ready.current = true;
    const pageGeneration = generation.current;
    try {
      const result = await request(message.command, message.payload);
      if (pageGeneration === generation.current)
        send({ type: "response", id: message.id, result });
      setLoading(false);
    } catch (error) {
      if (pageGeneration === generation.current)
        send({
          type: "response",
          id: message.id,
          error:
            error instanceof Error
              ? error.message
              : "This action could not be completed.",
        });
      setLoading(false);
    }
  }
  function retry() {
    generation.current += 1;
    ready.current = false;
    highestID.current = 0;
    setOutbox([]);
    setFailure("");
    setLoading(true);
    setAttempt((value) => value + 1);
  }
  return (
    <View style={styles.root}>
      <StatusBar barStyle="light-content" />
      <LocalPage
        key={attempt}
        messages={JSON.stringify(outbox)}
        onDelivered={(event) => {
          const id = event.nativeEvent.id;
          setOutbox((previous) => previous.filter((item) => item.id > id));
        }}
        style={styles.root}
        onMessage={receive}
        onFailure={(event) => {
          setFailure(event.nativeEvent.message);
          setLoading(false);
        }}
      />
      {loading && (
        <View style={styles.overlay}>
          <ScreenBackground />
          <Image
            source={{ uri: "brand-logo" }}
            accessibilityLabel="Vava logo"
            resizeMode="contain"
            style={styles.logo}
          />
          <ActivityIndicator
            color="#D4F07A"
            accessibilityLabel="Opening Vava"
          />
        </View>
      )}
      {!!failure && (
        <View style={styles.overlay}>
          <ScreenBackground />
          <Image
            source={{ uri: "brand-logo" }}
            accessibilityLabel="Vava logo"
            resizeMode="contain"
            style={styles.logo}
          />
          <Text style={styles.text}>{failure}</Text>
          <Pressable
            accessibilityRole="button"
            onPress={retry}
            style={styles.button}
          >
            <Text style={styles.text}>Try again</Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}
const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#0D211F" },
  overlay: {
    position: "absolute",
    top: 0,
    bottom: 0,
    left: 0,
    right: 0,
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "#0D211F",
    padding: 24,
    gap: 20,
  },
  logo: { width: 112, height: 112, borderRadius: 22 },
  text: { color: "#FFF2D4", fontSize: 18 },
  button: {
    minHeight: 44,
    padding: 14,
    backgroundColor: "#1A3830",
    borderRadius: 14,
  },
});
