import { SafeAreaView } from "react-native-safe-area-context";
import React, { useEffect, useMemo, useRef, useState } from "react";
import {
  Alert,
  FlatList,
  Image,
  KeyboardAvoidingView,
  Modal,
  PanResponder,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import {
  Conversation,
  Message,
  NativeCallVideo,
  Person,
  request,
  Snapshot,
} from "./native";
import { Route, useApp } from "./state";
import { ScreenBackground } from "./ScreenBackground";
import { Button, Card, Icon, Label, Page, ProfileActions } from "./ui";

function currentPerson(snapshot: Snapshot, person: Person): Person {
  const current =
    snapshot.chat.players.find((item) => item.id === person.id) ??
    snapshot.chat.histories.find((item) => item.person.id === person.id)
      ?.person;
  if (current) {
    return current;
  }
  const following =
    snapshot.state?.following.includes(person.id) ?? person.following;
  const blocked = snapshot.state?.blocked.includes(person.id) ?? person.blocked;
  let restriction = person.restriction;
  if (!person.isPublisher) {
    restriction = blocked
      ? "Unblock this player to chat."
      : !following
        ? "You must follow each other to start a chat."
        : "This player isn’t connected. Open Vava on both devices.";
  }
  return { ...person, following, blocked, restriction };
}

function portrait(snapshot: Snapshot, person: Person): string | undefined {
  const course = snapshot.catalog.courses.find(
    (item) => item.author.id === person.id,
  );
  if (course?.author.avatar) {
    return course.author.avatar;
  }
  return snapshot.catalog.shorts.find((item) => item.publisherID === person.id)
    ?.cover;
}

function Avatar({ person }: { person: Person }) {
  const { snapshot } = useApp();
  const uri = portrait(snapshot, person);
  return uri ? (
    <Image
      source={{ uri }}
      style={chatStyles.avatar}
      accessibilityIgnoresInvertColors
    />
  ) : (
    <View style={chatStyles.avatar}>
      <Text style={chatStyles.initial}>
        {person.name.slice(0, 1).toUpperCase()}
      </Text>
    </View>
  );
}

function ConversationRow({
  record,
  revealed,
  onReveal,
}: {
  record: Conversation;
  revealed: boolean;
  onReveal: (id?: string) => void;
}) {
  const { command, navigate } = useApp();
  const inbox = record.inbox;
  const preview = record.entries.at(-1)?.text ?? "";
  const swipe = useMemo(
    () =>
      PanResponder.create({
        onMoveShouldSetPanResponder: (_, gesture) => {
          if (
            Math.abs(gesture.dy) > 12 &&
            Math.abs(gesture.dy) > Math.abs(gesture.dx)
          ) {
            onReveal(undefined);
          }
          return (
            Math.abs(gesture.dx) > 12 &&
            Math.abs(gesture.dx) > Math.abs(gesture.dy) * 1.25
          );
        },
        onPanResponderRelease: (_, gesture) => {
          if (gesture.dx < -30) {
            onReveal(record.person.id);
          }
          if (gesture.dx > 30) {
            onReveal(undefined);
          }
        },
      }),
    [record.person.id, onReveal],
  );

  async function act(action: string) {
    const result =
      action === "delete"
        ? await command("chatHide", { id: record.person.id })
        : await command("chatInbox", {
            id: record.person.id,
            ...(action === "pin"
              ? { pinned: !inbox.pinned }
              : { unread: !inbox.unread }),
          });
    if (result) {
      onReveal(undefined);
    }
  }

  const actions = [
    { name: "pin", label: inbox.pinned ? "Unpin" : "Pin" },
    { name: "read", label: inbox.unread ? "Mark read" : "Mark unread" },
    { name: "delete", label: "Delete" },
  ];

  return (
    <View style={chatStyles.swipeRow} {...swipe.panHandlers}>
      {revealed && (
        <View style={chatStyles.inboxActions}>
          {actions.map((action) => (
            <Pressable
              key={action.name}
              accessibilityRole="button"
              accessibilityLabel={`${action.label} conversation with ${record.person.name}`}
              onPress={() => {
                void act(action.name);
              }}
              style={[
                chatStyles.inboxAction,
                action.name === "delete" && chatStyles.destructiveAction,
              ]}
            >
              <Text style={chatStyles.actionText}>{action.label}</Text>
            </Pressable>
          ))}
        </View>
      )}
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={record.person.name}
        accessibilityValue={{
          text: [preview, inbox.pinned && "Pinned", inbox.unread && "Unread"]
            .filter(Boolean)
            .join(", "),
        }}
        accessibilityActions={actions}
        onAccessibilityAction={(event) => {
          void act(event.nativeEvent.actionName);
        }}
        onPress={() => {
          if (revealed) {
            onReveal(undefined);
          } else {
            navigate({ name: "thread", person: record.person });
          }
        }}
        style={[
          chatStyles.conversation,
          inbox.pinned && chatStyles.pinned,
          revealed && { transform: [{ translateX: -216 }] },
        ]}
      >
        <Avatar person={record.person} />
        <View style={chatStyles.flex}>
          <Text style={chatStyles.personName}>{record.person.name}</Text>
          <Text numberOfLines={1} style={chatStyles.secondary}>
            {preview}
          </Text>
          {(inbox.pinned || inbox.unread) && (
            <Text style={chatStyles.status}>
              {[inbox.pinned && "Pinned", inbox.unread && "Unread"]
                .filter(Boolean)
                .join(" · ")}
            </Text>
          )}
        </View>
      </Pressable>
    </View>
  );
}

function Inbox() {
  const { snapshot, command, navigate } = useApp();
  const [revealed, setRevealed] = useState<string>();
  const histories = snapshot.chat.histories
    .filter((record) => !record.inbox.hidden)
    .sort((a, b) => {
      if (a.inbox.pinned !== b.inbox.pinned) {
        return a.inbox.pinned ? -1 : 1;
      }
      return (
        new Date(b.entries.at(-1)?.date ?? 0).getTime() -
        new Date(a.entries.at(-1)?.date ?? 0).getTime()
      );
    });
  return (
    <Page
      title="Chats"
      actions={
        <Icon
          name="add"
          label="Find players"
          onPress={() => navigate({ name: "discovery" })}
        />
      }
      onRefresh={async () => {
        setRevealed(undefined);
        return command("refresh");
      }}
    >
      {histories.length === 0 ? (
        <>
          <Label title>Keep the rally going</Label>
          <Label muted>Catch up with the players you meet.</Label>
          <Card>
            <Image source={{ uri: "icon-chats" }} style={chatStyles.emptyArt} />
            <Label title>Start a conversation</Label>
            <Label muted>Find a player and follow each other to chat.</Label>
            <Button
              title="Find players"
              primary
              onPress={() => navigate({ name: "discovery" })}
            />
          </Card>
        </>
      ) : (
        histories.map((record) => (
          <ConversationRow
            key={record.person.id}
            record={record}
            revealed={revealed === record.person.id}
            onReveal={setRevealed}
          />
        ))
      )}
    </Page>
  );
}

function Discovery() {
  const { snapshot, command, navigate, active } = useApp();
  useEffect(() => {
    if (active) {
      void command("chatStart");
    }
  }, [command, active]);
  return (
    <Page
      title="Find players"
      onRefresh={async () => {
        await command("chatStart");
      }}
    >
      <Label muted>Open Vava’s Find players screen on both iPhones.</Label>
      {snapshot.chat.playerCode && (
        <Label>Your player code · {snapshot.chat.playerCode}</Label>
      )}
      {snapshot.chat.discoveryIssue ? (
        <Label muted>{snapshot.chat.discoveryIssue}</Label>
      ) : (
        snapshot.chat.players.length === 0 && (
          <Card>
            <Label>Looking for nearby players…</Label>
          </Card>
        )
      )}
      {snapshot.chat.players.map((person) => (
        <Button
          key={person.id}
          title={`${person.name} · ${person.code}`}
          onPress={() => navigate({ name: "player", person })}
        />
      ))}
    </Page>
  );
}

function Player({ person: original }: { person: Person }) {
  const { snapshot, command, navigate } = useApp();
  const person = currentPerson(snapshot, original);
  function follow() {
    if (person.following) {
      void command("chatFollow", { id: person.id, enabled: false });
      return;
    }
    Alert.alert(
      "Confirm player",
      `Check that ${person.name} shows player code ${person.code} on their iPhone.`,
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Follow",
          onPress: () => {
            void command("chatFollow", { id: person.id, enabled: true });
          },
        },
      ],
    );
  }
  function block() {
    if (person.blocked) {
      void command("chatBlock", { id: person.id, enabled: false });
      return;
    }
    Alert.alert(
      `Block ${person.name}?`,
      "This player will no longer be able to chat or call you.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Block",
          style: "destructive",
          onPress: () => {
            void command("chatBlock", { id: person.id, enabled: true });
          },
        },
      ],
    );
  }
  return (
    <Page
      title={person.name}
      onRefresh={async () => {
        await command("chatStart");
      }}
    >
      <Card>
        <Avatar person={person} />
        <Label title>{person.name}</Label>
        <Label muted>Player code · {person.code}</Label>
      </Card>
      <ProfileActions
        followTitle={person.following ? "Unfollow" : "Follow"}
        following={person.following}
        blocked={person.blocked}
        onFollow={follow}
        onMessage={() => navigate({ name: "thread", person })}
        onBlock={block}
      />
    </Page>
  );
}

function MessageBubble({ entry, person }: { entry: Message; person: Person }) {
  const { command } = useApp();
  if (entry.kind === "notice") {
    return <Text style={chatStyles.notice}>{entry.text}</Text>;
  }
  const incoming = entry.kind === "incoming";
  const pending = entry.kind === "sending" || entry.kind === "unconfirmed";
  return (
    <View style={[chatStyles.messageRow, !incoming && chatStyles.outgoingRow]}>
      <View style={[chatStyles.bubble, !incoming && chatStyles.outgoingBubble]}>
        <Text style={[chatStyles.message, !incoming && chatStyles.darkText]}>
          {entry.text}
        </Text>
        <Text style={[chatStyles.timestamp, !incoming && chatStyles.darkText]}>
          {new Date(entry.date).toLocaleString("en", {
            month: "short",
            day: "numeric",
            hour: "numeric",
            minute: "2-digit",
          })}
        </Text>
        {pending && (
          <Text
            style={[chatStyles.timestamp, !incoming && chatStyles.darkText]}
          >
            Awaiting confirmation
          </Text>
        )}
        {pending && !entry.awaiting && (
          <Button
            title="Retry"
            onPress={() => {
              void command("chatSend", {
                id: person.id,
                text: entry.text,
                retryID: entry.id,
              });
            }}
          />
        )}
      </View>
    </View>
  );
}

function Thread({ person: original }: { person: Person }) {
  const { snapshot, command, navigate, back, active } = useApp();
  const person = currentPerson(snapshot, original);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const list = useRef<FlatList<Message>>(null);
  const nearBottom = useRef(true);
  const entries =
    snapshot.chat.histories.find((record) => record.person.id === person.id)
      ?.entries ?? [];
  const threadVisible = active && !snapshot.chat.call;

  useEffect(() => {
    if (!threadVisible) {
      return;
    }
    void command("chatOpen", { id: original.id });
    if (!original.isPublisher) {
      void command("chatStart");
    }
    return () => {
      void command("chatClose", { id: original.id });
    };
  }, [original.id, original.isPublisher, command, threadVisible]);

  async function send() {
    if (sending || !draft.trim()) {
      return;
    }
    setSending(true);
    try {
      const response = await command("chatSend", {
        id: person.id,
        text: draft,
      });
      if (response && !response.message) {
        setDraft("");
        nearBottom.current = true;
      }
    } finally {
      setSending(false);
    }
  }
  async function refresh() {
    setRefreshing(true);
    try {
      await command("refresh");
      if (!person.isPublisher) {
        await command("chatStart");
      }
    } finally {
      setRefreshing(false);
    }
  }
  return (
    <KeyboardAvoidingView style={chatStyles.flex} behavior="padding">
      <View style={chatStyles.threadHeader}>
        <Icon name="back" label="Back" onPress={back} />
        <Text style={chatStyles.threadTitle} numberOfLines={1}>
          {person.name}
        </Text>
        <Icon
          name="call"
          label="Voice call"
          onPress={() => {
            void command("chatCall", { id: person.id, video: false });
          }}
        />
        <Icon
          name="video"
          label="Video call"
          onPress={() => {
            void command("chatCall", { id: person.id, video: true });
          }}
        />
        <Icon
          name="more"
          label="View profile"
          onPress={() =>
            navigate(
              person.isPublisher
                ? { name: "publisher", id: person.id }
                : { name: "player", person },
            )
          }
        />
      </View>
      <FlatList
        ref={list}
        data={entries}
        keyExtractor={(entry) => entry.id}
        contentContainerStyle={chatStyles.messages}
        renderItem={({ item }) => (
          <MessageBubble entry={item} person={person} />
        )}
        keyboardShouldPersistTaps="handled"
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => {
              void refresh();
            }}
            tintColor="#D4F07A"
          />
        }
        onScroll={(event) => {
          const { contentOffset, contentSize, layoutMeasurement } =
            event.nativeEvent;
          nearBottom.current =
            contentSize.height - contentOffset.y - layoutMeasurement.height <
            90;
        }}
        scrollEventThrottle={32}
        onContentSizeChange={() => {
          if (nearBottom.current) {
            list.current?.scrollToEnd({ animated: false });
          }
        }}
      />
      <View style={chatStyles.composer}>
        {!!person.restriction && <Label muted>{person.restriction}</Label>}
        <View style={chatStyles.composerRow}>
          <TextInput
            value={draft}
            onChangeText={setDraft}
            style={chatStyles.input}
            placeholder="Message"
            placeholderTextColor="#C7D6C2"
            accessibilityLabel="Message"
            editable={!person.restriction && !sending}
            maxLength={2000}
            returnKeyType="send"
            onSubmitEditing={() => {
              void send();
            }}
          />
          <Button
            title={sending ? "Sending…" : "Send"}
            primary
            disabled={sending || !draft.trim() || !!person.restriction}
            onPress={() => {
              void send();
            }}
          />
        </View>
      </View>
    </KeyboardAvoidingView>
  );
}

function CallPreview() {
  const { active } = useApp();
  const attempt = useRef(0);
  const [preview, setPreview] = useState<{ id: number; video: boolean }>();
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!active) {
      setPreview(undefined);
      setStatus("");
      setBusy(false);
      return;
    }
    return () => {
      attempt.current += 1;
      void request("callPreviewStop").catch(() => {});
    };
  }, [active]);

  async function start(video: boolean) {
    const id = ++attempt.current;
    setPreview({ id, video });
    setStatus("");
    setBusy(true);
    try {
      const result = await request("callPreviewStart", { video });
      if (attempt.current === id) setStatus(result.message ?? "");
    } catch {
      if (attempt.current === id) {
        setStatus("Preview stopped. Try again to restart it.");
      }
    } finally {
      if (attempt.current === id) setBusy(false);
    }
  }

  return (
    <Page title="Call preview">
      {preview?.video && (
        <NativeCallVideo
          key={preview.id}
          localPreview
          style={chatStyles.callVideo}
          accessibilityLabel="Your camera preview"
        />
      )}
      <View accessibilityLiveRegion="polite">
        <Label muted>
          {busy
            ? "Checking access…"
            : status || "Check your microphone and front camera on this device."}
        </Label>
      </View>
      <Button
        title="Voice preview"
        disabled={busy}
        onPress={() => void start(false)}
      />
      <Button
        title="Video preview"
        primary
        disabled={busy}
        onPress={() => void start(true)}
      />
    </Page>
  );
}

export function ChatsScreen({ route }: { route: Route }) {
  if (route.name === "callPreview") {
    return <CallPreview />;
  }
  if (route.name === "discovery") {
    return <Discovery />;
  }
  if (route.name === "player" && route.person) {
    return <Player person={route.person} />;
  }
  if (route.name === "thread" && route.person) {
    return <Thread key={route.person.id} person={route.person} />;
  }
  return <Inbox />;
}

export function CallOverlay() {
  const { snapshot, command } = useApp();
  const call = snapshot.chat.call;
  const [muted, setMuted] = useState(false);
  const [changingMute, setChangingMute] = useState(false);
  useEffect(() => {
    setMuted(false);
  }, [call?.id]);
  if (!call) {
    return null;
  }
  const endTitle =
    call.phase === "incoming"
      ? "Decline"
      : call.phase === "ended"
        ? "Done"
        : "End call";
  async function toggleMute() {
    setChangingMute(true);
    try {
      if (await command("callMute", { muted: !muted })) {
        setMuted(!muted);
      }
    } finally {
      setChangingMute(false);
    }
  }
  return (
    <Modal
      visible
      animationType="slide"
      presentationStyle="fullScreen"
      onRequestClose={() => {
        void command("callEnd", { id: call.id });
      }}
    >
      <SafeAreaView style={chatStyles.flex}>
        <ScreenBackground />
        <ScrollView contentContainerStyle={chatStyles.callContent}>
          <Label title>{call.video ? "Video call" : "Voice call"}</Label>
          <Text style={chatStyles.callName}>{call.person.name}</Text>
          {!!call.detail && <Label muted>{call.detail}</Label>}
          {call.phase === "incoming" && (
            <Button
              title="Accept"
              primary
              onPress={() => {
                void command("callAnswer", { id: call.id });
              }}
            />
          )}
          {call.phase === "connected" && (
            <>
              {call.video && (
                <NativeCallVideo
                  style={chatStyles.callVideo}
                  accessibilityLabel="Remote video"
                />
              )}
              <Button
                title={muted ? "Unmute" : "Mute"}
                disabled={changingMute}
                onPress={() => {
                  void toggleMute();
                }}
              />
            </>
          )}
          <Button
            title={endTitle}
            danger={call.phase !== "ended"}
            onPress={() => {
              void command("callEnd", { id: call.id });
            }}
          />
        </ScrollView>
      </SafeAreaView>
    </Modal>
  );
}

const chatStyles = StyleSheet.create({
  flex: { flex: 1 },
  avatar: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: "#1A3830",
    alignItems: "center",
    justifyContent: "center",
  },
  initial: { fontFamily: "Kalam-Bold", fontSize: 22, color: "#FFF2D4" },
  conversation: {
    padding: 16,
    minHeight: 88,
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    borderRadius: 20,
    backgroundColor: "#1A3830",
    borderWidth: 1,
    borderColor: "#45614F",
  },
  pinned: { borderColor: "#D4F07A" },
  personName: { fontFamily: "Kalam-Bold", fontSize: 19, color: "#FFF2D4" },
  secondary: {
    fontFamily: "ComicNeue-Regular",
    fontSize: 14,
    color: "#C7D6C2",
  },
  status: {
    fontFamily: "ComicNeue-Regular",
    fontSize: 12,
    color: "#D4F07A",
    marginTop: 4,
  },
  swipeRow: { overflow: "hidden", borderRadius: 20 },
  inboxActions: {
    position: "absolute",
    right: 0,
    top: 0,
    bottom: 0,
    width: 216,
    flexDirection: "row",
  },
  inboxAction: {
    flex: 1,
    minHeight: 44,
    justifyContent: "center",
    paddingHorizontal: 4,
    backgroundColor: "#45614F",
  },
  destructiveAction: { backgroundColor: "#8D392C" },
  actionText: {
    fontFamily: "Kalam-Bold",
    fontSize: 13,
    color: "#FFF2D4",
    textAlign: "center",
  },
  emptyArt: {
    width: 72,
    height: 72,
    alignSelf: "center",
    resizeMode: "contain",
  },
  threadHeader: {
    paddingHorizontal: 12,
    minHeight: 56,
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
  },
  threadTitle: {
    fontFamily: "Kalam-Bold",
    fontSize: 23,
    color: "#FFF2D4",
    flex: 1,
    minWidth: 0,
  },
  messages: { padding: 18, gap: 12, flexGrow: 1 },
  messageRow: { flexDirection: "row", paddingRight: "15%" },
  outgoingRow: {
    justifyContent: "flex-end",
    paddingRight: 0,
    paddingLeft: "15%",
  },
  bubble: {
    flexShrink: 1,
    borderRadius: 20,
    padding: 14,
    gap: 4,
    backgroundColor: "#1A3830",
  },
  outgoingBubble: { backgroundColor: "#D4F07A" },
  message: { fontFamily: "ComicNeue-Regular", fontSize: 17, color: "#FFF2D4" },
  timestamp: {
    fontFamily: "ComicNeue-Regular",
    fontSize: 12,
    color: "#C7D6C2",
  },
  darkText: { color: "#0D211F" },
  notice: {
    fontFamily: "ComicNeue-Regular",
    fontSize: 14,
    color: "#C7D6C2",
    textAlign: "center",
    paddingVertical: 5,
  },
  composer: { paddingHorizontal: 18, paddingBottom: 8, gap: 6 },
  composerRow: { flexDirection: "row", alignItems: "center", gap: 8 },
  input: {
    flex: 1,
    minWidth: 0,
    minHeight: 44,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 12,
    backgroundColor: "#1A3830",
    color: "#FFF2D4",
    fontFamily: "ComicNeue-Regular",
    fontSize: 17,
  },
  callContent: { padding: 20, gap: 18, flexGrow: 1, justifyContent: "center" },
  callName: {
    fontFamily: "Kalam-Bold",
    fontSize: 28,
    color: "#FFF2D4",
    textAlign: "center",
  },
  callVideo: {
    width: "100%",
    aspectRatio: 1 / 1.12,
    backgroundColor: "#0D211F",
    borderRadius: 20,
    overflow: "hidden",
  },
});
