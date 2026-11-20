import React, { useCallback, useEffect, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Image,
  Pressable,
  StatusBar,
  StyleSheet,
  View,
} from "react-native";
import {
  SafeAreaProvider,
  SafeAreaView,
  initialWindowMetrics,
} from "react-native-safe-area-context";
import { request, Response, Snapshot, subscribe } from "./native";
import { AppContext, Route, useApp } from "./state";
import { Academy, CourseDetail, ReplayDetail, Watch } from "./Content";
import {
  BlockedPublishers,
  Credits,
  EditProfile,
  ImportVideo,
  Me,
  PublisherProfile,
  Settings,
  WalletScreen,
} from "./Profile";
import { Shorts } from "./Shorts";
import { ScreenBackground } from "./ScreenBackground";
import { CallOverlay, ChatsScreen } from "./Chats";
import { Button, colors, Icon, Label, styles } from "./ui";

const tabs = ["Academy", "Watch", "Shorts", "Chats", "Me"];
const rootStacks = (): Route[][] => tabs.map((name) => [{ name }]);

export default function App() {
  return (
    <SafeAreaProvider initialMetrics={initialWindowMetrics}>
      <VavaApp />
    </SafeAreaProvider>
  );
}

function VavaApp() {
  const [snapshot, setSnapshot] = useState<Snapshot>();
  const [failure, setFailure] = useState("");
  const [tab, setTab] = useState(0);
  const [stacks, setStacks] = useState<Route[][]>(rootStacks);
  const command = useCallback(
    async (
      name: string,
      payload: Record<string, unknown> = {},
    ): Promise<Response | undefined> => {
      try {
        const response = await request(name, payload);
        setSnapshot((previous) =>
          !previous || response.snapshot.revision >= previous.revision
            ? response.snapshot
            : previous,
        );
        setFailure("");
        if (response.message) Alert.alert("Vava", response.message);
        return response;
      } catch (error) {
        const message =
          error instanceof Error
            ? error.message
            : "Vava could not complete this action. Please try again.";
        if (name === "bootstrap") setFailure(message);
        else Alert.alert("Could not complete action", message);
        return undefined;
      }
    },
    [],
  );
  useEffect(() => {
    const unsubscribe = subscribe((incoming) => {
      setSnapshot((previous) =>
        !previous || incoming.revision >= previous.revision
          ? incoming
          : previous,
      );
    });
    void command("bootstrap");
    return unsubscribe;
  }, [command]);
  useEffect(() => {
    setStacks(rootStacks());
    setTab(0);
  }, [snapshot?.signedIn, snapshot?.state?.me.id]);
  function navigate(route: Route) {
    setStacks((previous) =>
      previous.map((stack, index) =>
        index === tab ? [...stack, route] : stack,
      ),
    );
  }
  function back() {
    setStacks((previous) =>
      previous.map((stack, index) =>
        index === tab && stack.length > 1 ? stack.slice(0, -1) : stack,
      ),
    );
  }
  if (!snapshot)
    return (
      <SafeAreaView style={appStyles.root}>
        <ScreenBackground />
        <StatusBar barStyle="light-content" />
        <View style={[styles.flex, appStyles.center]}>
          <Image
            source={{ uri: "brand-logo" }}
            accessibilityLabel="Vava logo"
            resizeMode="contain"
            style={appStyles.loadingLogo}
          />
          {failure ? (
            <>
              <Label>{failure}</Label>
              <Button
                title="Try again"
                onPress={() => {
                  void command("bootstrap");
                }}
              />
            </>
          ) : (
            <ActivityIndicator
              color={colors.lime}
              accessibilityLabel="Opening Vava"
            />
          )}
        </View>
      </SafeAreaView>
    );
  const currentRoute = stacks[tab].at(-1)?.name;
  const showingShorts =
    snapshot.signedIn && (currentRoute === "Shorts" || currentRoute === "shorts");
  const context = {
    snapshot,
    command,
    navigate,
    back,
    canGoBack: stacks[tab].length > 1,
    active: true,
  };
  return (
    <SafeAreaView style={appStyles.root}>
      {!showingShorts && <ScreenBackground />}
      <StatusBar barStyle="light-content" />
      <AppContext.Provider value={context}>
        {!snapshot.signedIn ? (
          <Welcome />
        ) : (
          <>
            <View style={styles.flex}>
              {stacks.map((stack, tabIndex) => (
                <View
                  key={tabs[tabIndex]}
                  style={[styles.flex, tabIndex !== tab && appStyles.hidden]}
                >
                  {stack.map((route, index) => (
                    <AppContext.Provider
                      key={`${index}-${route.name}-${route.id || route.person?.id || ""}`}
                      value={{
                        ...context,
                        canGoBack: index > 0,
                        active:
                          tabIndex === tab &&
                          index === stack.length - 1 &&
                          !snapshot.chat.call,
                      }}
                    >
                      <View
                        style={[
                          styles.flex,
                          index !== stack.length - 1 && appStyles.hidden,
                        ]}
                      >
                        <Screen route={route} />
                      </View>
                    </AppContext.Provider>
                  ))}
                </View>
              ))}
            </View>
            {stacks[tab].length === 1 && (
              <View accessibilityRole="tablist" style={appStyles.dock}>
                {tabs.map((name, index) => (
                  <Pressable
                    key={name}
                    accessibilityRole="tab"
                    accessibilityLabel={name}
                    accessibilityState={{ selected: index === tab }}
                    onPress={() => setTab(index)}
                    style={[
                      appStyles.tab,
                      index === tab && appStyles.selectedTab,
                    ]}
                  >
                    <Image
                      source={{ uri: `icon-${name.toLowerCase()}` }}
                      resizeMode="contain"
                      style={{ width: 28, height: 28 }}
                    />
                    <Label style={{ fontSize: 12, fontFamily: "Kalam-Bold" }}>
                      {name}
                    </Label>
                  </Pressable>
                ))}
              </View>
            )}
            <CallOverlay />
          </>
        )}
      </AppContext.Provider>
    </SafeAreaView>
  );
}
function Welcome() {
  const { snapshot, command } = useApp();
  const [accepted, setAccepted] = useState(false);
  const [busy, setBusy] = useState(false);
  return (
    <View style={appStyles.welcome}>
      <View style={appStyles.coverArea}>
        <Image
          source={{ uri: "brand-logo" }}
          accessibilityLabel="Vava logo"
          resizeMode="contain"
          style={appStyles.cover}
        />
      </View>
      <View style={{ gap: 10 }}>
        <Label muted>
          Watch the point. Practice the shot. Find your next partner.
        </Label>
        <View style={styles.row}>
          <Pressable
            accessibilityRole="checkbox"
            accessibilityLabel="Accept the agreements"
            aria-checked={accepted}
            disabled={busy}
            style={styles.iconButton}
            onPress={() => setAccepted((checked) => !checked)}
          >
            <View style={[appStyles.checkbox, accepted && appStyles.checked]}>
              {accepted && (
                <Image source={{ uri: "icon-check" }} style={appStyles.checkmark} />
              )}
            </View>
          </Pressable>
          <View style={appStyles.agreementText}>
            <Label>I agree to the</Label>
            <AgreementLink
              title="Terms of Service"
              url={snapshot.agreements.terms}
            />
            <Label>and</Label>
            <AgreementLink
              title="Privacy Policy"
              url={snapshot.agreements.privacy}
            />
          </View>
        </View>
        <Button
          title={busy ? "Opening…" : "Log in"}
          primary
          disabled={busy || !accepted}
          onPress={async () => {
            setBusy(true);
            await command("login", { accepted });
            setBusy(false);
          }}
        />
      </View>
    </View>
  );
}
function AgreementLink({ title, url }: { title: string; url: string }) {
  const { command } = useApp();
  return (
    <Pressable
      accessibilityRole="link"
      onPress={() => {
        void command("openURL", { url });
      }}
      style={{ minHeight: 24, justifyContent: "center" }}
    >
      <Label style={{ textDecorationLine: "underline" }}>{title}</Label>
    </Pressable>
  );
}
function Screen({ route }: { route: Route }) {
  switch (route.name) {
    case "Academy":
      return <Academy />;
    case "Watch":
      return <Watch />;
    case "Shorts":
    case "shorts":
      return <Shorts selectedID={route.id} />;
    case "Chats":
    case "callPreview":
    case "discovery":
    case "player":
    case "thread":
      return <ChatsScreen route={route} />;
    case "Me":
      return <Me />;
    case "course":
      return <CourseDetail id={route.id!} />;
    case "replay":
      return <ReplayDetail id={route.id!} />;
    case "publisher":
      return (
        <PublisherProfile id={route.id!} initialCollection={route.collection} />
      );
    case "settings":
      return <Settings />;
    case "editProfile":
      return <EditProfile />;
    case "blocked":
      return <BlockedPublishers />;
    case "wallet":
      return <WalletScreen />;
    case "import":
      return <ImportVideo />;
    case "credits":
      return <Credits id={route.id} />;
    default:
      return (
        <View style={styles.page}>
          <Label>This page is unavailable.</Label>
        </View>
      );
  }
}
const appStyles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.ink },
  center: { justifyContent: "center", padding: 24, gap: 20 },
  hidden: { display: "none" },
  dock: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    flexDirection: "row",
    backgroundColor: colors.ink,
    borderColor: colors.line,
    borderWidth: 1,
    borderRadius: 22,
    marginHorizontal: 13,
    marginBottom: 6,
    minHeight: 62,
  },
  tab: {
    flex: 1,
    minHeight: 60,
    paddingVertical: 5,
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 20,
  },
  selectedTab: { backgroundColor: colors.line },
  welcome: {
    flex: 1,
    padding: 20,
    gap: 18,
    justifyContent: "space-between",
  },
  coverArea: { flex: 1, minHeight: 0, alignItems: "center" },
  agreementText: {
    flex: 1,
    flexDirection: "row",
    flexWrap: "wrap",
    alignItems: "center",
    columnGap: 4,
    rowGap: 2,
  },
  checkbox: {
    width: 27,
    height: 27,
    borderWidth: 1,
    borderColor: colors.secondary,
    borderRadius: 7,
    alignItems: "center",
    justifyContent: "center",
  },
  checked: { backgroundColor: colors.lime, borderColor: colors.lime },
  checkmark: { width: 22, height: 22 },
  loadingLogo: {
    width: 112,
    height: 112,
    alignSelf: "center",
    borderRadius: 22,
  },
  cover: {
    width: "100%",
    height: "100%",
    maxWidth: 144,
    maxHeight: 144,
    borderRadius: 16,
  },
});
