import React, { useState } from "react";
import { Pressable, View } from "react-native";
import { Clip, Course, Publisher, Snapshot } from "./native";
import { useApp } from "./state";
import {
  Avatar,
  Button,
  Card,
  Icon,
  Label,
  Page,
  Photo,
  Field,
  choose,
  colors,
  confirm,
  styles,
} from "./ui";

export function visible(snapshot: Snapshot, id: string, publisher?: string) {
  return (
    !snapshot.state?.hidden.includes(id) &&
    (!publisher || !snapshot.state?.blocked.includes(publisher))
  );
}
export function allClips(snapshot: Snapshot) {
  return [...snapshot.catalog.shorts, ...snapshot.ownedClips];
}
export function publisherFor(
  snapshot: Snapshot,
  id: string,
): Publisher | undefined {
  const course = snapshot.catalog.courses.find((item) => item.author.id === id);
  if (course) return course.author;
  const clip = snapshot.catalog.shorts.find((item) => item.publisherID === id);
  return clip ? { id, name: clip.publisher, avatar: clip.cover } : undefined;
}
export function engagement(snapshot: Snapshot, clip: Clip) {
  return {
    likes:
      clip.engagement.likes + Number(snapshot.state?.likes.includes(clip.id)),
    saves:
      clip.engagement.saves + Number(snapshot.state?.saves.includes(clip.id)),
    shares:
      clip.engagement.shares + (snapshot.state?.shareCounts[clip.id] || 0),
    comments:
      clip.editorialComments.length +
      (snapshot.state?.commentsByClip[clip.id]?.length || 0),
  };
}
export function rotate<T>(items: T[], offset: number): T[] {
  if (!items.length) return items;
  const index = offset % items.length;
  return [...items.slice(index), ...items.slice(0, index)];
}
export function useContentActions() {
  const { command, navigate } = useApp();
  function report(id: string) {
    choose(
      "Report content",
      [
        "Harassment or hate",
        "Inappropriate content",
        "Misleading information",
        "Rights concern",
        "Something else",
      ],
      (reason) => {
        confirm(
          "Save report?",
          "This records your report and hides the content. Review is unavailable.",
          "Save report",
          () => {
            void command("report", { id, reason });
          },
        );
      },
    );
  }
  function block(id: string) {
    confirm(
      "Block publisher?",
      "Their works will be hidden. You can unblock them in Settings.",
      "Block",
      () => {
        void command("block", { id, enabled: true });
      },
      true,
    );
  }
  function more(id: string, publisherID?: string, credit = false) {
    const options = [
      ...(credit ? ["Source and license"] : []),
      "Hide content",
      ...(publisherID ? ["Report content", "Block publisher"] : []),
    ];
    choose("Content actions", options, (value) => {
      if (value === "Source and license") navigate({ name: "credits", id });
      if (value === "Report content") report(id);
      if (value === "Block publisher" && publisherID) block(publisherID);
      if (value === "Hide content")
        confirm(
          "Hide content?",
          "This hides the content from your lists.",
          "Hide",
          () => {
            void command("activity", { id, kind: "hide", enabled: true });
          },
        );
    });
  }
  return { report, block, more };
}
export function Author({
  publisher,
  tutorials,
}: {
  publisher: Publisher;
  tutorials?: boolean;
}) {
  const { navigate } = useApp();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`View ${publisher.name} profile`}
      onPress={() =>
        navigate({
          name: "publisher",
          id: publisher.id,
          collection: tutorials ? "Tutorials" : "Shorts",
        })
      }
      style={[styles.row, { minHeight: 44, flex: 1 }]}
    >
      <Avatar uri={publisher.avatar} size={40} />
      <View style={styles.flex}>
        <Label style={{ fontFamily: "Kalam-Bold" }}>{publisher.name}</Label>
        <Label muted style={{ fontSize: 13 }}>
          {tutorials ? "Coaching reference" : "Recording source"}
        </Label>
      </View>
    </Pressable>
  );
}
export function CourseCard({ course }: { course: Course }) {
  const { snapshot, navigate } = useApp();
  const { more } = useContentActions();
  const price =
    course.price === 0
      ? "Free"
      : snapshot.wallet?.owned.includes(course.id)
        ? "Unlocked"
        : `${course.price} coins`;
  return (
    <Card>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={`${course.title}, ${price}`}
        onPress={() => navigate({ name: "course", id: course.id })}
        style={{ gap: 8 }}
      >
        <Photo uri={course.cover} ratio={2.17} />
        <Label style={{ color: colors.lime, fontSize: 13 }}>
          {course.category.toUpperCase()} / {course.minutes} MIN
        </Label>
        <Label title style={{ fontSize: 25 }}>
          {course.title}
        </Label>
        <Label muted>{course.detail}</Label>
        <Label style={{ color: colors.lime }}>{price}</Label>
      </Pressable>
      <View style={styles.row}>
        <Author publisher={course.author} tutorials />
        <Icon
          name="more"
          label="More lesson actions"
          onPress={() => more(course.id, course.author.id)}
        />
      </View>
    </Card>
  );
}
export function Academy() {
  const { snapshot, command } = useApp();
  const [searching, setSearching] = useState(false);
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState("All topics");
  const [price, setPrice] = useState("All prices");
  const [order, setOrder] = useState(0);
  const courses = snapshot.catalog.courses.filter(
    (course) =>
      visible(snapshot, course.id, course.author.id) &&
      (category === "All topics" ||
        course.category === category ||
        (category === "Saved" && snapshot.state?.saves.includes(course.id))) &&
      (price === "All prices" ||
        (course.price === 0 ? price === "Free" : price === "Coin unlock")) &&
      `${course.title} ${course.category} ${course.detail} ${course.author.name}`
        .toLowerCase()
        .includes(query.trim().toLowerCase()),
  );
  function filter() {
    choose("Filter lessons", ["Topics", "Prices"], (value) => {
      if (value === "Topics")
        choose(
          "Topics",
          [
            "All topics",
            "Saved",
            ...new Set(
              snapshot.catalog.courses.map((course) => course.category),
            ),
          ],
          setCategory,
        );
      else choose("Prices", ["All prices", "Free", "Coin unlock"], setPrice);
    });
  }
  return (
    <Page
      title="Academy"
      onRefresh={async () => {
        const result = await command("refresh");
        if (result) setOrder((value) => value + 1);
        return result;
      }}
      actions={
        <>
          <Icon
            name="search"
            label="Search lessons"
            onPress={() => {
              setSearching(!searching);
              setQuery("");
            }}
          />
          <Icon name="filter" label="Filter lessons" onPress={filter} />
        </>
      }
    >
      {searching && (
        <Field
          label="Search lessons"
          value={query}
          onChangeText={setQuery}
          autoFocus
        />
      )}
      <Label muted style={{ fontSize: 20 }}>
        Build a better point.
      </Label>
      {rotate(courses, order).map((course) => (
        <CourseCard key={course.id} course={course} />
      ))}
      {!courses.length && (
        <Card>
          <Label>No matching lessons.</Label>
        </Card>
      )}
    </Page>
  );
}
export function CourseDetail({ id }: { id: string }) {
  const { snapshot, command, navigate } = useApp();
  const { more } = useContentActions();
  const [busy, setBusy] = useState(false);
  const course = snapshot.catalog.courses.find((item) => item.id === id);
  if (!course)
    return (
      <Page title="Lesson">
        <Label>This lesson is unavailable.</Label>
      </Page>
    );
  const unlocked = course.price === 0 || snapshot.wallet?.owned.includes(id);
  const completed = snapshot.state?.practice[id] || [];
  const saved = snapshot.state?.saves.includes(id);
  function unlock() {
    if ((snapshot.wallet?.balance || 0) < course!.price)
      confirm(
        "More coins needed",
        `Your balance is ${snapshot.wallet?.balance || 0} coins.`,
        "Open wallet",
        () => navigate({ name: "wallet" }),
      );
    else
      confirm(
        "Unlock this course?",
        `Spend ${course!.price} coins on ${course!.title}.`,
        "Unlock",
        () => {
          void command("unlock", { id });
        },
      );
  }
  return (
    <Page
      title="Lesson"
      actions={
        <Icon
          name="more"
          label="More lesson actions"
          onPress={() => more(id, course.author.id)}
        />
      }
    >
      <Label
        title
        numberOfLines={1}
        adjustsFontSizeToFit
        minimumFontScale={0.75}
        style={{ fontSize: 24 }}
      >
        {course.title}
      </Label>
      {!visible(snapshot, id, course.author.id) ? (
        <Label muted>This lesson is hidden from your lists.</Label>
      ) : (
        <>
          <Photo uri={course.cover} />
          <Author publisher={course.author} tutorials />
          <Label style={{ color: colors.lime }}>
            {course.level} / {course.minutes} min
          </Label>
          <Label>{course.detail}</Label>
          <Button
            title={saved ? "Remove from saved" : "Save lesson"}
            onPress={() => {
              void command("activity", { id, kind: "save", enabled: !saved });
            }}
          />
          {unlocked ? (
            <>
              <Label title>
                Practice {completed.length}/{course.steps?.length || 0}
              </Label>
              {course.steps?.map((step, index) => (
                <Card key={index}>
                  <Label style={{ color: colors.lime }}>
                    Drill {index + 1}
                  </Label>
                  <Label>{step}</Label>
                  <Button
                    title={
                      completed.includes(index) ? "Completed" : "Mark complete"
                    }
                    primary={completed.includes(index)}
                    disabled={busy}
                    onPress={async () => {
                      setBusy(true);
                      await command("practice", {
                        id,
                        step: index,
                        completed: !completed.includes(index),
                      });
                      setBusy(false);
                    }}
                  />
                </Card>
              )) || <Label>Practice steps are unavailable.</Label>}
            </>
          ) : (
            <Card>
              <Label title>Unlock the practice plan</Label>
              <Label>Unlock once to access the practice plan.</Label>
              <Button
                title={`Unlock for ${course.price} coins`}
                primary
                onPress={unlock}
              />
            </Card>
          )}
          <Card>
            <Label title>Coaching reference</Label>
            <Button
              title={course.referenceName}
              onPress={() => {
                void command("openURL", { url: course.reference });
              }}
            />
          </Card>
        </>
      )}
    </Page>
  );
}
export function Watch() {
  const { snapshot, command, navigate } = useApp();
  const [searching, setSearching] = useState(false);
  const [query, setQuery] = useState("");
  const [event, setEvent] = useState("All events");
  const [order, setOrder] = useState(0);
  const replays = snapshot.catalog.replays.filter(
    (replay) =>
      visible(snapshot, replay.id) &&
      (event === "All events" ||
        event === replay.event ||
        (event === "Saved" && snapshot.state?.saves.includes(replay.id))) &&
      `${replay.title} ${replay.event}`
        .toLowerCase()
        .includes(query.trim().toLowerCase()),
  );
  return (
    <Page
      title="Watch"
      onRefresh={async () => {
        const result = await command("refresh");
        if (result) setOrder((value) => value + 1);
        return result;
      }}
      actions={
        <>
          <Icon
            name="search"
            label="Search replays"
            onPress={() => {
              setSearching(!searching);
              setQuery("");
            }}
          />
          <Icon
            name="filter"
            label="Filter by event"
            onPress={() =>
              choose(
                "Events",
                [
                  "All events",
                  "Saved",
                  ...new Set(
                    snapshot.catalog.replays.map((item) => item.event),
                  ),
                ],
                setEvent,
              )
            }
          />
        </>
      }
    >
      {searching && (
        <Field
          label="Search matches"
          value={query}
          onChangeText={setQuery}
          autoFocus
        />
      )}
      <Label muted>Match replays</Label>
      {rotate(replays, order).map((replay) => (
        <Pressable
          key={replay.id}
          accessibilityRole="button"
          accessibilityLabel={replay.title}
          onPress={() => navigate({ name: "replay", id: replay.id })}
        >
          <Card>
            <Photo uri={replay.cover} />
            <Label style={{ color: colors.lime }}>
              {replay.event.toUpperCase()}
            </Label>
            <Label title>{replay.title}</Label>
            <Label style={{ color: colors.lime }}>View replay</Label>
          </Card>
        </Pressable>
      ))}
      {!replays.length && (
        <Card>
          <Label>No replays match these filters.</Label>
        </Card>
      )}
    </Page>
  );
}
export function ReplayDetail({ id }: { id: string }) {
  const { snapshot, command, back } = useApp();
  const replay = snapshot.catalog.replays.find((item) => item.id === id);
  if (!replay)
    return (
      <Page title="Replay">
        <Label>This replay is unavailable.</Label>
      </Page>
    );
  const saved = snapshot.state?.saves.includes(id);
  return (
    <Page title="Replay">
      <Photo uri={replay.cover} />
      <Label style={{ color: colors.lime }}>{replay.event.toUpperCase()}</Label>
      <Label title>{replay.title}</Label>
      <Label muted>Official replay · {replay.publisher}</Label>
      <Button
        title="Watch on the publisher's site"
        primary
        onPress={() => {
          void command("openURL", { url: replay.source });
        }}
      />
      <Button
        title={saved ? "Remove from saved" : "Save replay"}
        onPress={() => {
          void command("activity", { id, kind: "save", enabled: !saved });
        }}
      />
      <Button
        title="Share replay"
        onPress={() => {
          void command("share", { url: replay.source });
        }}
      />
      <Button
        title="Hide replay"
        onPress={() =>
          confirm(
            "Hide this replay?",
            "This hides the replay from your lists.",
            "Hide replay",
            async () => {
              if (
                await command("activity", { id, kind: "hide", enabled: true })
              )
                back();
            },
          )
        }
      />
    </Page>
  );
}
