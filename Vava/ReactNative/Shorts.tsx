import React, { useEffect, useLayoutEffect, useRef, useState } from "react";
import {
  AccessibilityInfo,
  Animated,
  Easing,
  Image,
  KeyboardAvoidingView,
  Modal,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  View,
} from "react-native";
import { Clip, NativeVideo } from "./native";
import { useApp } from "./state";
import {
  allClips,
  engagement,
  publisherFor,
  rotate,
  useContentActions,
  visible,
} from "./Content";
import { Avatar, Button, Card, colors, Field, Icon, Label, styles } from "./ui";

export function Shorts({ selectedID }: { selectedID?: string }) {
  const { snapshot, command, navigate, back, canGoBack, active } = useApp();
  const { more } = useContentActions();
  const clips = allClips(snapshot).filter((item) =>
    visible(snapshot, item.id, item.publisherID),
  );
  const [currentID, setCurrentID] = useState(selectedID || clips[0]?.id);
  const [paused, setPaused] = useState(false);
  const [searching, setSearching] = useState(false);
  const [query, setQuery] = useState("");
  const [savedOnly, setSavedOnly] = useState(false);
  const [comments, setComments] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [notice, setNotice] = useState("");
  const [progress, setProgress] = useState({ currentTime: 0, duration: 0 });
  const [seekFraction, setSeekFraction] = useState<number>();
  const [trackWidth, setTrackWidth] = useState(1);
  const [playbackError, setPlaybackError] = useState("");
  const tapTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const lastTap = useRef(0);
  const lastSwipe = useRef(0);
  const pageHeight = useRef(0);
  const displacement = useRef(new Animated.Value(0)).current;
  const settling = useRef(false);
  const reducedMotion = useRef(false);
  const touchStart = useRef<{
    x: number;
    y: number;
    axis?: "vertical" | "horizontal";
  } | null>(null);
  const index = Math.max(
    0,
    clips.findIndex((item) => item.id === currentID),
  );
  const clip = clips[index];
  const previous = clips[index - 1];
  const following = clips[index + 1];

  useEffect(() => {
    let mounted = true;
    function updateMotion(value: boolean) {
      if (mounted) reducedMotion.current = value;
    }
    void AccessibilityInfo.isReduceMotionEnabled().then(updateMotion);
    const change = AccessibilityInfo.addEventListener(
      "reduceMotionChanged",
      updateMotion,
    );
    return () => {
      mounted = false;
      change?.remove();
    };
  }, []);

  useLayoutEffect(() => {
    touchStart.current = null;
    settling.current = false;
    displacement.setValue(0);
    return () => displacement.stopAnimation();
  }, [active, comments, clip?.id, currentID, displacement, searching]);

  useEffect(() => {
    setPaused(false);
    setComments(false);
    setPlaybackError("");
    setSeekFraction(undefined);
    setProgress({ currentTime: 0, duration: 0 });
    return () => {
      if (tapTimer.current) clearTimeout(tapTimer.current);
    };
  }, [clip?.id]);
  function settlePage(offset: number, nextID?: string, after?: () => void) {
    if (settling.current) return;
    settling.current = true;
    Animated.timing(displacement, {
      toValue: offset,
      duration: reducedMotion.current ? 0 : 240,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: false,
    }).start(({ finished }) => {
      if (!finished) return;
      if (nextID && nextID !== currentID) {
        setCurrentID(nextID);
      } else {
        settling.current = false;
        displacement.setValue(0);
        after?.();
      }
    });
  }
  function page(direction: number) {
    const next = clips[index + direction];
    if (next) settlePage(-direction * pageHeight.current, next.id);
  }
  async function refresh() {
    if (refreshing) return;
    setRefreshing(true);
    const result = await command("refresh");
    if (result) {
      const refreshed = allClips(result.snapshot).filter((item) =>
        visible(result.snapshot, item.id, item.publisherID),
      );
      const position = refreshed.findIndex((item) => item.id === clip?.id);
      const next = refreshed[(position + 1) % refreshed.length];
      if (next && !searching && next.id === following?.id) {
        settlePage(-pageHeight.current, next.id);
      } else if (next) {
        setCurrentID(next.id);
      }
      setNotice("Shorts updated");
    }
    setRefreshing(false);
  }
  function updateSwipe(x: number, y: number, ended = false) {
    const origin = touchStart.current;
    if (!origin || settling.current) return;
    if (ended) touchStart.current = null;
    const dx = x - origin.x;
    const dy = y - origin.y;
    if (!origin.axis && Math.max(Math.abs(dx), Math.abs(dy)) > 8) {
      origin.axis = Math.abs(dy) > Math.abs(dx) ? "vertical" : "horizontal";
    }
    if (!origin.axis) return;
    lastSwipe.current = Date.now();
    if (tapTimer.current) clearTimeout(tapTimer.current);
    lastTap.current = 0;
    if (origin.axis === "horizontal") return;

    const next = dy < 0 ? following : previous;
    if (!ended) {
      const height = pageHeight.current;
      const offset = Math.max(-height, Math.min(height, dy));
      displacement.setValue(next ? offset : offset * 0.18);
      return;
    }
    if (Math.abs(dy) > 45 && next) {
      settlePage(dy < 0 ? -pageHeight.current : pageHeight.current, next.id);
    } else {
      const refreshOnRelease = dy > 45 && index === 0;
      settlePage(0, undefined, refreshOnRelease ? () => void refresh() : undefined);
    }
  }
  function cancelSwipe() {
    if (touchStart.current?.axis === "vertical") settlePage(0);
    touchStart.current = null;
  }
  function tapVideo() {
    const now = Date.now();
    if (settling.current || refreshing || now - lastSwipe.current < 400) return;
    if (clip && now - lastTap.current < 300) {
      if (tapTimer.current) clearTimeout(tapTimer.current);
      void command("activity", { id: clip.id, kind: "like", enabled: true });
      lastTap.current = 0;
    } else {
      lastTap.current = now;
      tapTimer.current = setTimeout(() => setPaused((value) => !value), 300);
    }
  }
  const counts = clip ? engagement(snapshot, clip) : undefined;
  const liked = clip && snapshot.state?.likes.includes(clip.id);
  const saved = clip && snapshot.state?.saves.includes(clip.id);
  const results = clips.filter(
    (item) =>
      (!savedOnly || snapshot.state?.saves.includes(item.id)) &&
      `${item.title} ${item.detail} ${item.publisher}`
        .toLowerCase()
        .includes(query.trim().toLowerCase()),
  );
  const publisher = clip && publisherFor(snapshot, clip.publisherID);
  const progressFraction = Math.min(
    1,
    progress.currentTime / Math.max(progress.duration, 1),
  );
  const progressPosition = `${progressFraction * 100}%` as const;
  const pageTransform = { transform: [{ translateY: displacement }] };
  return (
    <View
      style={shortStyles.player}
      onLayout={(event) => {
        pageHeight.current = event.nativeEvent.layout.height;
      }}
    >
      <Animated.View
        pointerEvents="none"
        testID="shorts-video-pages"
        style={[StyleSheet.absoluteFill, pageTransform]}
      >
        {previous && <ShortsPreview clip={previous} top="-100%" />}
        {clip && (
          <NativeVideo
            key={clip.id}
            uri={clip.media}
            poster={clip.cover || undefined}
            paused={paused || !active || searching}
            seekFraction={seekFraction}
            onProgress={(event) => setProgress(event.nativeEvent)}
            onError={(event) => setPlaybackError(event.nativeEvent.message)}
            style={StyleSheet.absoluteFill}
          />
        )}
        {following && <ShortsPreview clip={following} top="100%" />}
      </Animated.View>
      <Pressable
        onTouchStart={(event) => {
          const touches = event.nativeEvent.touches;
          if (touches.length !== 1) {
            cancelSwipe();
            return;
          }
          if (settling.current || refreshing || searching || comments) return;
          const point = touches[0];
          touchStart.current = { x: point.pageX, y: point.pageY };
        }}
        onTouchMove={(event) => {
          const point = event.nativeEvent.touches[0];
          if (point) updateSwipe(point.pageX, point.pageY);
        }}
        onTouchEnd={(event) => {
          const point = event.nativeEvent.changedTouches[0];
          if (point) updateSwipe(point.pageX, point.pageY, true);
          else cancelSwipe();
        }}
        onTouchCancel={cancelSwipe}
        style={StyleSheet.absoluteFill}
        testID="shorts-swipe-surface"
        accessibilityRole="button"
        accessibilityLabel={paused ? "Play video" : "Pause video"}
        accessibilityHint="Swipe up for the next video. Swipe down at the first video to refresh."
        accessibilityActions={[
          { name: "increment", label: "Next video" },
          { name: "decrement", label: "Previous video" },
        ]}
        onAccessibilityAction={(event) =>
          page(event.nativeEvent.actionName === "increment" ? 1 : -1)
        }
        onPress={tapVideo}
      />
      <View style={[styles.header, shortStyles.toolbar]}>
        {canGoBack && <Icon name="back" label="Back" onPress={back} />}
        <Label title style={[styles.flex, shortStyles.heading]}>
          Shorts
        </Label>
        <Icon
          name={searching ? "close" : "search"}
          label={searching ? "Close search" : "Search shorts"}
          onPress={() => {
            setSearching(!searching);
            setQuery("");
          }}
        />
        <Icon
          name="add"
          label="Add a video"
          onPress={() => navigate({ name: "import" })}
        />
      </View>
      {!clip && (
        <View style={[styles.flex, { justifyContent: "center", padding: 20 }]}>
          <Label>No clips to show.</Label>
          <Button
            title="Add a video"
            onPress={() => navigate({ name: "import" })}
          />
        </View>
      )}
      {clip && !searching && (
        <Animated.View
          pointerEvents="box-none"
          style={[shortStyles.footer, { bottom: canGoBack ? 4 : 80 }, pageTransform]}
        >
          <View pointerEvents="box-none" style={shortStyles.footerRow}>
            <View
              pointerEvents="box-none"
              testID="shorts-caption"
              style={shortStyles.caption}
            >
              <Label muted style={shortStyles.position}>
                {index + 1} of {clips.length}
                {clip.duration > 0 ? ` · ${clip.duration}s` : ""}
              </Label>
              <Pressable
                accessibilityRole="button"
                onPress={() =>
                  navigate(
                    clip.submissionID
                      ? { name: "Me" }
                      : { name: "publisher", id: clip.publisherID },
                  )
                }
              >
                <Label numberOfLines={1} style={shortStyles.byline}>
                  {clip.publisher}
                </Label>
              </Pressable>
              <Label title numberOfLines={2} style={shortStyles.clipTitle}>
                {clip.title}
              </Label>
              <Label numberOfLines={2}>{clip.detail}</Label>
              {!clip.submissionID && (
                <Label muted style={shortStyles.note}>
                  Includes estimated activity
                </Label>
              )}
              {!!notice && (
                <Label muted style={shortStyles.note} aria-live="polite">
                  {notice}
                </Label>
              )}
              {!!playbackError && (
                <Label style={shortStyles.error}>{playbackError}</Label>
              )}
            </View>
            <View
              pointerEvents="box-none"
              testID="shorts-actions"
              style={shortStyles.rail}
            >
              <Pressable
                accessibilityRole="button"
                accessibilityLabel={
                  clip.submissionID
                    ? "View your profile"
                    : `View ${clip.publisher} profile`
                }
                onPress={() =>
                  navigate(
                    clip.submissionID
                      ? { name: "Me" }
                      : { name: "publisher", id: clip.publisherID },
                  )
                }
                style={styles.iconButton}
              >
                <Avatar
                  uri={
                    clip.submissionID
                      ? snapshot.state?.me.avatarURI
                      : publisher?.avatar
                  }
                  size={38}
                />
              </Pressable>
              <Metric
                name={liked ? "like-selected" : "like-outline"}
                label={liked ? "Unlike clip" : "Like clip"}
                count={counts!.likes}
                onPress={() => {
                  void command("activity", {
                    id: clip.id,
                    kind: "like",
                    enabled: !liked,
                  });
                }}
              />
              <Metric
                name="comment"
                label="Comments"
                count={counts!.comments}
                onPress={() => setComments(true)}
              />
              <Metric
                name={saved ? "save-selected" : "save-outline"}
                label={saved ? "Remove saved clip" : "Save clip"}
                count={counts!.saves}
                onPress={() => {
                  void command("activity", {
                    id: clip.id,
                    kind: "save",
                    enabled: !saved,
                  });
                }}
              />
              <Metric
                name="share"
                label="Share clip"
                count={counts!.shares}
                onPress={() => {
                  void command("share", { id: clip.id });
                }}
              />
              {!clip.submissionID && (
                <Icon
                  name="more"
                  label="More clip actions"
                  onPress={() => more(clip.id, clip.publisherID, !!clip.source)}
                />
              )}
            </View>
          </View>
          <Pressable
            accessibilityRole="adjustable"
            accessibilityLabel="Video progress"
            accessibilityValue={{
              min: 0,
              max: Math.max(1, Math.round(progress.duration)),
              now: Math.round(progress.currentTime),
            }}
            accessibilityActions={[
              { name: "increment", label: "Forward ten seconds" },
              { name: "decrement", label: "Back ten seconds" },
            ]}
            onAccessibilityAction={(event) =>
              setSeekFraction(
                Math.max(
                  0,
                  Math.min(
                    1,
                    (progress.currentTime +
                      (event.nativeEvent.actionName === "increment"
                        ? 10
                        : -10)) /
                      Math.max(progress.duration, 1),
                  ),
                ),
              )
            }
            onLayout={(event) => setTrackWidth(event.nativeEvent.layout.width)}
            onPress={(event) =>
              setSeekFraction(
                Math.max(
                  0,
                  Math.min(1, event.nativeEvent.locationX / trackWidth),
                ),
              )
            }
            style={shortStyles.seekButton}
          >
            <View pointerEvents="none" style={shortStyles.track}>
              <View style={[shortStyles.trackFill, { width: progressPosition }]} />
              <View style={[shortStyles.trackThumb, { left: progressPosition }]} />
            </View>
          </Pressable>
        </Animated.View>
      )}
      {searching && (
        <View style={shortStyles.search}>
          <Field
            label="Find a player, rally or match"
            value={query}
            onChangeText={setQuery}
            autoFocus
          />
          <Button
            title={savedOnly ? "Showing saved clips" : "All clips"}
            onPress={() => setSavedOnly(!savedOnly)}
          />
          <ScrollView
            keyboardShouldPersistTaps="handled"
            contentContainerStyle={{ gap: 12, paddingBottom: 20 }}
            refreshControl={
              <RefreshControl
                refreshing={refreshing}
                onRefresh={refresh}
                tintColor={colors.lime}
              />
            }
          >
            {results.map((item) => (
              <Button
                key={item.id}
                title={`${item.title} · ${item.publisher}`}
                onPress={() => {
                  setCurrentID(item.id);
                  setSearching(false);
                }}
              />
            ))}
            {!results.length && <Label>No matching clips.</Label>}
          </ScrollView>
        </View>
      )}
      {clip && (
        <Discussion
          clip={clip}
          visible={comments && active}
          onClose={() => setComments(false)}
        />
      )}
    </View>
  );
}
function ShortsPreview({ clip, top }: { clip: Clip; top: "-100%" | "100%" }) {
  return (
    <View aria-hidden pointerEvents="none" style={[shortStyles.preview, { top }]}>
      {clip.cover ? (
        <Image
          source={{ uri: clip.cover }}
          resizeMode="contain"
          style={StyleSheet.absoluteFill}
        />
      ) : (
        <Label title numberOfLines={2}>{clip.title}</Label>
      )}
    </View>
  );
}
function Metric({
  name,
  label,
  count,
  onPress,
}: {
  name: string;
  label: string;
  count: number;
  onPress: () => void;
}) {
  const formattedCount = count.toLocaleString("en");
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`${label}, ${formattedCount}`}
      onPress={onPress}
      style={({ pressed }) => [shortStyles.metric, pressed && styles.dim]}
    >
      <Image
        source={{ uri: `icon-${name}` }}
        style={shortStyles.metricIcon}
        resizeMode="contain"
      />
      <Label aria-hidden numberOfLines={1} style={shortStyles.metricCount}>
        {formattedCount}
      </Label>
    </Pressable>
  );
}
function Discussion({
  clip,
  visible: open,
  onClose,
}: {
  clip: Clip;
  visible: boolean;
  onClose: () => void;
}) {
  const { snapshot, command } = useApp();
  const [body, setBody] = useState("");
  const [reply, setReply] = useState<{ id: string; name: string }>();
  const [busy, setBusy] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [order, setOrder] = useState(0);
  const [limit, setLimit] = useState(30);
  const local = snapshot.state?.commentsByClip[clip.id] || [];
  const rows = [
    ...local.map((item) => ({
      id: item.id,
      name: item.author.name,
      body: item.body,
      detail: [
        "Private comment",
        item.replyTo
          ? `Reply to ${local.find((parent) => parent.id === item.replyTo)?.author.name || "Vava Editorial"}`
          : "",
        item.postedAt ? new Date(item.postedAt).toLocaleString("en") : "",
      ]
        .filter(Boolean)
        .join(" · "),
    })),
    ...rotate(clip.editorialComments, order).map((item) => ({
      ...item,
      name: "Vava Editorial",
      detail: "",
    })),
  ];
  return (
    <Modal
      transparent
      visible={open}
      animationType="slide"
      onRequestClose={onClose}
    >
      <KeyboardAvoidingView behavior="padding" style={styles.flex}>
        <Pressable
          style={styles.flex}
          accessibilityLabel="Close comments"
          onPress={onClose}
        />
        <View accessibilityViewIsModal style={shortStyles.comments}>
          <View style={styles.row}>
            <Label title style={[styles.flex, { fontSize: 25 }]}>
              {rows.length} {rows.length === 1 ? "comment" : "comments"}
            </Label>
            <Icon name="close" label="Close comments" onPress={onClose} />
          </View>
          <ScrollView
            keyboardShouldPersistTaps="handled"
            contentContainerStyle={{ gap: 8 }}
            refreshControl={
              <RefreshControl
                refreshing={refreshing}
                tintColor={colors.lime}
                onRefresh={async () => {
                  setRefreshing(true);
                  if (await command("refresh")) setOrder((value) => value + 1);
                  setRefreshing(false);
                }}
              />
            }
          >
            <Label muted>
              {rows.length
                ? "Vava’s notes follow the footage. Comments you add are private."
                : "No comments yet. Add a private comment."}
            </Label>
            {rows.slice(0, limit).map((row) => (
              <Card key={row.id}>
                <Label style={{ fontFamily: "Kalam-Bold" }}>{row.name}</Label>
                {row.detail ? (
                  <Label muted style={{ fontSize: 13 }}>
                    {row.detail}
                  </Label>
                ) : null}
                <Label>{row.body}</Label>
                <Button
                  title="Reply"
                  onPress={() => setReply({ id: row.id, name: row.name })}
                />
              </Card>
            ))}
            {rows.length > limit && (
              <Button
                title="More comments"
                onPress={() => setLimit((value) => value + 30)}
              />
            )}
          </ScrollView>
          {reply && (
            <View style={styles.row}>
              <Label style={styles.flex}>Replying to {reply.name}</Label>
              <Icon
                name="close"
                label="Cancel reply"
                onPress={() => setReply(undefined)}
              />
            </View>
          )}
          <View style={styles.row}>
            <View style={styles.flex}>
              <Field
                label="Add a private comment"
                value={body}
                onChangeText={setBody}
                maxLength={200}
              />
            </View>
            <Button
              title={busy ? "Saving…" : "Save"}
              primary
              disabled={busy || !body.trim()}
              onPress={async () => {
                setBusy(true);
                const result = await command("comment", {
                  clip: clip.id,
                  body: body.trim(),
                  replyTo: reply?.id,
                });
                setBusy(false);
                if (result) {
                  setBody("");
                  setReply(undefined);
                }
              }}
            />
          </View>
        </View>
      </KeyboardAvoidingView>
    </Modal>
  );
}
const shortStyles = StyleSheet.create({
  player: { flex: 1, backgroundColor: colors.ink, overflow: "hidden" },
  preview: {
    position: "absolute",
    left: 0,
    right: 0,
    height: "100%",
    backgroundColor: colors.ink,
    alignItems: "center",
    justifyContent: "center",
    padding: 18,
  },
  toolbar: { zIndex: 1 },
  heading: { fontSize: 34 },
  footer: { position: "absolute", left: 18, right: 16 },
  footerRow: { flexDirection: "row", alignItems: "flex-end", gap: 12 },
  caption: { flex: 1, minWidth: 0, gap: 5 },
  position: { fontSize: 14 },
  byline: { color: colors.lime },
  clipTitle: { fontSize: 26 },
  note: { fontSize: 12 },
  error: { color: colors.coral },
  rail: { width: 46, flexShrink: 0, alignItems: "center", gap: 3 },
  metric: {
    width: 46,
    minHeight: 48,
    alignItems: "center",
    justifyContent: "center",
  },
  metricIcon: { width: 29, height: 29 },
  metricCount: { fontFamily: "Kalam-Bold", fontSize: 12 },
  seekButton: { height: 44, justifyContent: "center" },
  track: { height: 6, borderRadius: 3, backgroundColor: colors.line },
  trackFill: { height: 6, borderRadius: 3, backgroundColor: colors.lime },
  trackThumb: {
    position: "absolute",
    top: "50%",
    width: 24,
    height: 14,
    borderRadius: 7,
    backgroundColor: colors.ivory,
    transform: [{ translateX: -12 }, { translateY: -7 }],
  },
  search: {
    flex: 1,
    backgroundColor: "rgba(13,33,31,0.92)",
    padding: 16,
    gap: 10,
  },
  comments: {
    height: "55%",
    minHeight: 230,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    backgroundColor: colors.ink,
    padding: 16,
    gap: 8,
  },
});
