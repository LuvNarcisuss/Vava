import React, { useEffect, useRef, useState } from "react";
import {
  Alert,
  PanResponder,
  Pressable,
  useWindowDimensions,
  View,
} from "react-native";
import { Clip } from "./native";
import { useApp } from "./state";
import {
  allClips,
  engagement,
  publisherFor,
  rotate,
  useContentActions,
  visible,
} from "./Content";
import {
  Avatar,
  Button,
  Card,
  choose,
  colors,
  confirm,
  Field,
  Icon,
  Label,
  Page,
  Photo,
  ProfileActions,
  styles,
  Tabs,
} from "./ui";

function Summary({
  name,
  bio,
  avatar,
  clips,
  following,
  publisher = false,
}: {
  name: string;
  bio: string;
  avatar?: string;
  clips: Clip[];
  following: number;
  publisher?: boolean;
}) {
  const { snapshot } = useApp();
  const totals = clips.reduce(
    (sum, clip) => {
      const value = engagement(snapshot, clip);
      return { likes: sum.likes + value.likes, saves: sum.saves + value.saves };
    },
    { likes: 0, saves: 0 },
  );
  return (
    <Card>
      <View style={styles.row}>
        <Avatar uri={avatar} size={72} />
        <View style={styles.flex}>
          <Label title>{name}</Label>
          <Label muted>{bio}</Label>
        </View>
      </View>
      <View style={styles.row}>
        {[
          [totals.likes, "Likes"],
          [totals.saves, "Saves"],
          [following, publisher ? "Your follows" : "Following"],
        ].map(([value, title]) => (
          <View key={title} style={[styles.flex, { alignItems: "center" }]}>
            <Label title style={{ fontSize: 23 }}>
              {value.toLocaleString("en")}
            </Label>
            <Label muted>{title}</Label>
          </View>
        ))}
      </View>
    </Card>
  );
}
export function ClipGrid({ clips }: { clips: Clip[] }) {
  const { snapshot, navigate } = useApp();
  const { fontScale } = useWindowDimensions();
  return (
    <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 10 }}>
      {clips.map((clip) => {
        const counts = engagement(snapshot, clip);
        return (
          <Pressable
            key={clip.id}
            accessibilityRole="button"
            accessibilityLabel={`${clip.title}, ${counts.likes} likes, ${counts.saves} saves`}
            onPress={() => navigate({ name: "shorts", id: clip.id })}
            style={{ width: fontScale > 1.5 ? "100%" : "48%" }}
          >
            <Card>
              <Photo uri={clip.cover} ratio={1.4} />
              <Label style={{ fontFamily: "Kalam-Bold" }}>{clip.title}</Label>
              <Label muted style={{ fontSize: 13 }}>
                {counts.likes.toLocaleString("en")} likes ·{" "}
                {counts.saves.toLocaleString("en")} saves
              </Label>
            </Card>
          </Pressable>
        );
      })}
    </View>
  );
}
export function Me() {
  const { snapshot, command, navigate } = useApp();
  const [collection, setCollection] = useState("Shorts");
  const [order, setOrder] = useState(0);
  const collections = ["Shorts", "Tutorials", "Liked", "Saved"];
  const touchStart = useRef({ x: 0, y: 0 });
  function selectBySwipe(dx: number, dy: number) {
    if (Math.abs(dx) <= 45 || Math.abs(dx) <= Math.abs(dy) * 1.4) return;
    setCollection(
      (current) =>
        collections[
          Math.max(
            0,
            Math.min(
              collections.length - 1,
              collections.indexOf(current) + (dx < 0 ? 1 : -1),
            ),
          )
        ],
    );
  }
  const pan = PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponderCapture: (_, gesture) =>
      Math.abs(gesture.dx) > 20 &&
      Math.abs(gesture.dx) > Math.abs(gesture.dy) * 1.4,
    onPanResponderGrant: (event) => {
      touchStart.current = {
        x: event.nativeEvent.pageX,
        y: event.nativeEvent.pageY,
      };
    },
    onPanResponderRelease: (event, gesture) =>
      selectBySwipe(
        gesture.dx || event.nativeEvent.pageX - touchStart.current.x,
        gesture.dy || event.nativeEvent.pageY - touchStart.current.y,
      ),
  });
  const state = snapshot.state!;
  const selectedIDs = collection === "Liked" ? state.likes : state.saves;
  const clips = (
    collection === "Shorts"
      ? snapshot.ownedClips
      : allClips(snapshot).filter((clip) => selectedIDs.includes(clip.id))
  ).filter((clip) => visible(snapshot, clip.id, clip.publisherID));
  const courses = snapshot.catalog.courses.filter(
    (course) =>
      visible(snapshot, course.id, course.author.id) &&
      (collection === "Saved"
        ? state.saves.includes(course.id)
        : snapshot.wallet?.owned.includes(course.id) ||
          !!state.practice[course.id]?.length),
  );
  const replays = snapshot.catalog.replays.filter(
    (replay) => state.saves.includes(replay.id) && visible(snapshot, replay.id),
  );
  return (
    <Page
      title="Me"
      actions={
        <Icon
          name="settings"
          label="Settings"
          onPress={() => navigate({ name: "settings" })}
        />
      }
      onRefresh={async () => {
        const result = await command("refresh");
        if (result) setOrder((value) => value + 1);
        return result;
      }}
    >
      <Summary
        name={state.me.name}
        bio={state.me.bio || "Add a bio in Settings."}
        avatar={state.me.avatarURI}
        clips={snapshot.ownedClips}
        following={state.following.length}
      />
      <Button
        title={`Wallet · ${(snapshot.wallet?.balance || 0).toLocaleString("en")} coins`}
        primary
        onPress={() => navigate({ name: "wallet" })}
      />
      {snapshot.wallet?.hasPurchaseIssue && (
        <Label style={{ color: colors.coral }}>
          Some purchases could not be added to your wallet. Open Wallet to
          retry.
        </Label>
      )}
      <Tabs
        values={collections}
        selected={collection}
        onSelect={setCollection}
      />
      <View {...pan.panHandlers} style={{ gap: 12, minHeight: 180 }}>
        {collection === "Shorts" && (
          <>
            <Button
              title="Add a video"
              onPress={() => navigate({ name: "import" })}
            />
            {!clips.length && <Label muted>No works yet.</Label>}
          </>
        )}
        {collection === "Tutorials" ? (
          <>
            <Label title>My learning</Label>
            {!courses.length && (
              <Label muted>
                Start a lesson or unlock a practice plan to see it here.
              </Label>
            )}
          </>
        ) : (
          <ClipGrid clips={rotate(clips, order)} />
        )}
        {(collection === "Tutorials" || collection === "Saved") &&
          rotate(courses, order).map((course) => (
            <Card key={course.id}>
              <Button
                title={course.title}
                onPress={() => navigate({ name: "course", id: course.id })}
              />
              <Label muted>
                {state.practice[course.id]?.length || 0}/
                {course.steps?.length || 0} practice steps completed
              </Label>
            </Card>
          ))}
        {collection === "Saved" &&
          replays.map((replay) => (
            <Button
              key={replay.id}
              title={replay.title}
              onPress={() => navigate({ name: "replay", id: replay.id })}
            />
          ))}
        {collection === "Liked" && !clips.length && (
          <Label muted>No liked clips yet.</Label>
        )}
        {collection === "Saved" &&
          !clips.length &&
          !courses.length &&
          !replays.length && <Label muted>No saved items yet.</Label>}
        {collection === "Shorts" && snapshot.ownedClips.length > 0 && (
          <Card>
            <Label title>Manage works</Label>
            {snapshot.ownedClips.map((clip) => (
              <Button
                key={clip.id}
                title={`Remove ${clip.title}`}
                danger
                onPress={() =>
                  confirm(
                    "Remove video?",
                    "This removes your imported copy and its activity from Vava.",
                    "Remove",
                    () => {
                      void command("removeVideo", { id: clip.submissionID });
                    },
                    true,
                  )
                }
              />
            ))}
          </Card>
        )}
      </View>
    </Page>
  );
}
export function PublisherProfile({
  id,
  initialCollection,
}: {
  id: string;
  initialCollection?: string;
}) {
  const { snapshot, command, navigate } = useApp();
  const { report, block } = useContentActions();
  const [collection, setCollection] = useState(initialCollection || "Shorts");
  const publisher = publisherFor(snapshot, id);
  if (!publisher)
    return (
      <Page title="Publisher">
        <Label>This publisher is unavailable.</Label>
      </Page>
    );
  const following = snapshot.state?.following.includes(id) || false;
  const blocked = snapshot.state?.blocked.includes(id) || false;
  const works = snapshot.catalog.shorts.filter(
    (clip) => clip.publisherID === id,
  );
  const courses = snapshot.catalog.courses.filter(
    (course) => course.author.id === id,
  );
  const reportable = [...works, ...courses].filter(
    (work) => !snapshot.state?.hidden.includes(work.id),
  );
  return (
    <Page
      title="Publisher"
      actions={
        reportable.length ? (
          <Icon
            name="report"
            label="Report content"
            onPress={() =>
              Alert.alert("Choose content to report", undefined, [
                ...reportable.map((work) => ({
                  text: work.title,
                  onPress: () => report(work.id),
                })),
                { text: "Cancel", style: "cancel" },
              ])
            }
          />
        ) : undefined
      }
    >
      <Summary
        name={publisher.name}
        bio={courses.length ? "Coaching reference" : "Recording source"}
        avatar={publisher.avatar}
        clips={works}
        following={following ? 1 : 0}
        publisher
      />
      {!!works.length && (
        <Label muted style={{ fontSize: 12 }}>
          Includes estimated activity
        </Label>
      )}
      <ProfileActions
        followTitle={following ? "Following" : "Follow"}
        following={following}
        blocked={blocked}
        messageDisabled={blocked}
        onFollow={() => {
          void command("follow", { id, enabled: !following });
        }}
        onMessage={() =>
          navigate({
            name: "thread",
            person: {
              id,
              name: publisher.name,
              isPublisher: true,
              code: "",
              following,
              blocked,
            },
          })
        }
        onBlock={() => {
          if (blocked) void command("block", { id, enabled: false });
          else block(id);
        }}
      />
      {publisher.website && (
        <Button
          title="Open source website"
          onPress={() => {
            void command("openURL", { url: publisher.website });
          }}
        />
      )}
      <Tabs
        values={["Shorts", "Tutorials"]}
        selected={collection}
        onSelect={setCollection}
      />
      {blocked ? (
        <Label muted>Works are hidden while this publisher is blocked.</Label>
      ) : collection === "Shorts" ? (
        <>
          <ClipGrid
            clips={works.filter((clip) => visible(snapshot, clip.id, id))}
          />
          {!works.some((clip) => visible(snapshot, clip.id, id)) && (
            <Label muted>No shorts to show.</Label>
          )}
        </>
      ) : (
        <>
          {courses
            .filter((course) => visible(snapshot, course.id, id))
            .map((course) => (
              <Button
                key={course.id}
                title={course.title}
                onPress={() => navigate({ name: "course", id: course.id })}
              />
            ))}
          {!courses.some((course) => visible(snapshot, course.id, id)) && (
            <Label muted>No tutorials to show.</Label>
          )}
        </>
      )}
      {id === "table-tennis-england" && (
        <>
          <Button
            title="Team photo credit"
            onPress={() => {
              void command("openURL", {
                url: "https://commons.wikimedia.org/wiki/File:20220814_ECM22_Table_Tennis_8658.jpg",
              });
            }}
          />
          <Label muted>
            Tin-Tin Ho representing England · Ailura · CC BY-SA 3.0 AT · Cropped
          </Label>
        </>
      )}
    </Page>
  );
}
export function Settings() {
  const { snapshot, command, navigate } = useApp();
  return (
    <Page title="Settings">
      <Button
        title="Edit profile"
        onPress={() => navigate({ name: "editProfile" })}
      />
      <Button
        title="Media credits"
        onPress={() => navigate({ name: "credits" })}
      />
      <Button
        title="Blocked publishers"
        onPress={() => navigate({ name: "blocked" })}
      />
      <Button
        title="Terms of Service"
        onPress={() => {
          void command("openURL", { url: snapshot.agreements.terms });
        }}
      />
      <Button
        title="Privacy Policy"
        onPress={() => {
          void command("openURL", { url: snapshot.agreements.privacy });
        }}
      />
      <Button
        title="Log out"
        onPress={() =>
          confirm(
            "Log out?",
            "You can log back in to access your profile, saved activity, and wallet.",
            "Log out",
            () => {
              void command("signOut");
            },
          )
        }
      />
      <Button
        title="Delete account"
        danger
        onPress={() =>
          confirm(
            "Delete account?",
            "This permanently deletes your profile, saved activity, imported copies, coins, and course access in Vava. Your original videos stay in Photos.",
            "Delete account",
            () => {
              void command("deleteAccount");
            },
            true,
          )
        }
      />
    </Page>
  );
}
export function EditProfile() {
  const { snapshot, command, back } = useApp();
  const [name, setName] = useState(snapshot.state?.me.name || "");
  const [bio, setBio] = useState(snapshot.state?.me.bio || "");
  const [avatarURI, setAvatarURI] = useState(snapshot.state?.me.avatarURI);
  const [busy, setBusy] = useState(false);
  const valid =
    name.trim().length > 0 &&
    name.trim().length <= 40 &&
    bio.trim().length <= 180;
  return (
    <Page title="Edit profile">
      <Avatar uri={avatarURI} size={72} />
      <Button
        title="Choose profile photo"
        disabled={busy}
        onPress={async () => {
          setBusy(true);
          const result = await command("pickAvatar");
          if (result?.avatarURI) setAvatarURI(result.avatarURI);
          setBusy(false);
        }}
      />
      <Field
        label="Display name"
        value={name}
        onChangeText={setName}
        maxLength={40}
      />
      <Field
        label="Bio"
        value={bio}
        onChangeText={setBio}
        multiline
        maxLength={180}
      />
      <Label muted>
        Use 1–40 characters for your name and up to 180 for your bio.
      </Label>
      <Button
        title={busy ? "Saving…" : "Save profile"}
        primary
        disabled={busy || !valid}
        onPress={async () => {
          setBusy(true);
          const result = await command("editProfile", {
            name: name.trim(),
            bio: bio.trim(),
            avatarURI,
          });
          setBusy(false);
          if (result) back();
        }}
      />
    </Page>
  );
}
export function BlockedPublishers() {
  const { snapshot, command, navigate } = useApp();
  const blocked = snapshot.state?.blocked || [];
  const people = [
    ...snapshot.chat.players,
    ...snapshot.chat.histories.map((history) => history.person),
  ];
  return (
    <Page title="Blocked publishers">
      {blocked.map((id) => {
        const publisher = publisherFor(snapshot, id);
        const person = people.find((item) => item.id === id);
        return (
          <Card key={id}>
            <Button
              title={publisher?.name || person?.name || id}
              onPress={() => {
                if (publisher) navigate({ name: "publisher", id });
                else if (person) navigate({ name: "player", person });
              }}
            />
            <Button
              title="Unblock"
              onPress={() => {
                void command(publisher ? "block" : "chatBlock", {
                  id,
                  enabled: false,
                });
              }}
            />
          </Card>
        );
      })}
      {!blocked.length && (
        <Label muted>No publishers or players are blocked.</Label>
      )}
    </Page>
  );
}
export function WalletScreen() {
  const { snapshot, command } = useApp();
  const { fontScale } = useWindowDimensions();
  const [selected, setSelected] = useState<string>();
  const [buying, setBuying] = useState(false);
  useEffect(() => {
    void command("walletRefresh");
  }, [command]);
  const wallet = snapshot.wallet!;
  const pack = wallet.packs.find((item) => item.productID === selected);
  return (
    <Page
      title="Wallet"
      onRefresh={async () => {
        const result = await command("walletRefresh");
        return result?.snapshot.wallet?.catalogStatus === "ready"
          ? result
          : undefined;
      }}
    >
      <Card>
        <Label title>{wallet.balance.toLocaleString("en")} coins</Label>
        <Label muted>Unlock more practice plans.</Label>
      </Card>
      {wallet.hasPurchaseIssue && (
        <Card>
          <Label>Some purchases could not be added to your wallet.</Label>
          <Button
            title={
              wallet.retrying ? "Recovering purchases…" : "Retry purchases"
            }
            disabled={wallet.retrying}
            onPress={() => {
              void command("retryPurchases");
            }}
          />
        </Card>
      )}
      <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 8 }}>
        {wallet.packs.map((item) => (
          <Pressable
            key={item.productID}
            disabled={!item.price || !wallet.paymentsAllowed || buying}
            accessibilityRole="button"
            accessibilityLabel={`${item.coins} coins, ${item.price || "Unavailable"}`}
            accessibilityState={{
              selected: item.productID === selected,
              disabled: !item.price || !wallet.paymentsAllowed || buying,
            }}
            onPress={() => setSelected(item.productID)}
            style={{
              width: fontScale > 1.5 ? "100%" : "31%",
              padding: 10,
              minHeight: 90,
              borderRadius: 14,
              justifyContent: "center",
              backgroundColor:
                item.productID === selected ? colors.line : colors.panel,
              opacity: item.price ? 1 : 0.5,
            }}
          >
            <Label style={{ textAlign: "center", fontFamily: "Kalam-Bold" }}>
              {item.coins.toLocaleString("en")}
            </Label>
            <Label muted style={{ textAlign: "center" }}>
              {item.price || "Unavailable"}
            </Label>
          </Pressable>
        ))}
      </View>
      <Button
        title={
          buying
            ? "Purchasing…"
            : pack?.price
              ? `Buy · ${pack.price}`
              : "Choose a coin pack"
        }
        primary
        disabled={
          !pack?.price || !wallet.paymentsAllowed || wallet.busy || buying
        }
        onPress={async () => {
          if (!pack?.price) return;
          setBuying(true);
          await command("buy", {
            productID: pack.productID,
            price: pack.price,
          });
          setBuying(false);
        }}
      />
      <Label muted>{wallet.catalogMessage}</Label>
      <Label title>Wallet activity</Label>
      {wallet.entries.map((entry) => (
        <Card key={entry.id}>
          <Label>{entry.title}</Label>
          <Label
            style={{ color: entry.amount > 0 ? colors.lime : colors.coral }}
          >
            {entry.amount > 0 ? "+" : ""}
            {entry.amount.toLocaleString("en")} coins
          </Label>
          <Label muted>{new Date(entry.date).toLocaleString("en")}</Label>
        </Card>
      ))}
      {!wallet.entries.length && (
        <Label muted>No purchases or spending yet.</Label>
      )}
    </Page>
  );
}
export function ImportVideo() {
  const { command, back } = useApp();
  const [title, setTitle] = useState("");
  const [accepted, setAccepted] = useState(false);
  const [busy, setBusy] = useState(false);
  return (
    <Page title="Add a video">
      <Label>Choose a table tennis video up to three minutes long.</Label>
      <Field
        label="Video title"
        value={title}
        onChangeText={setTitle}
        maxLength={80}
        editable={!busy}
      />
      <Button
        title={
          accepted
            ? "Permission confirmed"
            : "I have permission to use this video"
        }
        primary={accepted}
        disabled={busy}
        onPress={() => setAccepted(!accepted)}
      />
      <Button
        title={busy ? "Preparing video…" : "Choose and save video"}
        primary
        disabled={!accepted || !title.trim() || busy}
        onPress={async () => {
          setBusy(true);
          const response = await command("importVideo", {
            title: title.trim(),
            accepted,
          });
          setBusy(false);
          if (response?.message === "Video saved.") back();
        }}
      />
    </Page>
  );
}
export function Credits({ id }: { id?: string }) {
  const { snapshot, command, navigate } = useApp();
  const clip = snapshot.catalog.shorts.find((item) => item.id === id);
  if (id && clip)
    return (
      <Page title="Source credit">
        <Photo uri={clip.cover} />
        <Label title>{clip.publisher}</Label>
        <Label>{clip.title}</Label>
        <Label style={{ color: colors.lime }}>{clip.license}</Label>
        <Label>
          Adapted for iPhone playback. The source page identifies the original
          recording.
        </Label>
        {clip.source && (
          <Button
            title="Open original recording"
            onPress={() => {
              void command("openURL", { url: clip.source });
            }}
          />
        )}
        {clip.licenseURL && (
          <Button
            title="View license"
            onPress={() => {
              void command("openURL", { url: clip.licenseURL });
            }}
          />
        )}
      </Page>
    );
  return (
    <Page title="Media credits">
      {snapshot.catalog.shorts.map((item) => (
        <Button
          key={item.id}
          title={`${item.title} · ${item.publisher}`}
          onPress={() => navigate({ name: "credits", id: item.id })}
        />
      ))}
      {snapshot.catalog.replays.map((item) => (
        <Button
          key={item.id}
          title={`${item.title} · ${item.publisher}`}
          onPress={() => {
            void command("openURL", { url: item.source });
          }}
        />
      ))}
    </Page>
  );
}
