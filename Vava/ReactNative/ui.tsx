import React, { PropsWithChildren, useState } from "react";
import {
  Alert,
  Image,
  KeyboardAvoidingView,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TextInputProps,
  TextStyle,
  View,
  ViewStyle,
  StyleProp,
  TextProps,
} from "react-native";
import { useApp } from "./state";

export const colors = {
  ink: "#0D211F",
  panel: "#1A3830",
  line: "#45614F",
  ivory: "#FFF2D4",
  secondary: "#C7D6C2",
  lime: "#D4F07A",
  coral: "#FF6B52",
};
export function Label({
  children,
  muted,
  title,
  style,
  ...props
}: PropsWithChildren<
  { muted?: boolean; title?: boolean; style?: StyleProp<TextStyle> } & TextProps
>) {
  return (
    <Text
      {...props}
      style={[styles.text, muted && styles.muted, title && styles.title, style]}
    >
      {children}
    </Text>
  );
}
export function Button({
  title,
  onPress,
  primary,
  danger,
  disabled,
  style,
}: {
  title: string;
  onPress: () => void;
  primary?: boolean;
  danger?: boolean;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled: !!disabled }}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.button,
        primary && styles.primary,
        style,
        (pressed || disabled) && styles.dim,
      ]}
    >
      <Label
        style={[
          styles.buttonText,
          primary && { color: colors.ink },
          danger && { color: colors.coral },
        ]}
      >
        {title}
      </Label>
    </Pressable>
  );
}
export function ProfileActions({
  followTitle,
  following,
  blocked,
  messageDisabled,
  onFollow,
  onMessage,
  onBlock,
}: {
  followTitle: string;
  following: boolean;
  blocked: boolean;
  messageDisabled?: boolean;
  onFollow: () => void;
  onMessage: () => void;
  onBlock: () => void;
}) {
  return (
    <View style={styles.profileActions}>
      <Button
        title={followTitle}
        primary={!following}
        disabled={blocked}
        onPress={onFollow}
        style={styles.profileActionButton}
      />
      <Button
        title="Message"
        disabled={messageDisabled}
        onPress={onMessage}
        style={styles.profileActionButton}
      />
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={blocked ? "Unblock" : "Block"}
        onPress={onBlock}
        style={({ pressed }) => [
          styles.profileBlockButton,
          blocked && styles.profileBlockSelected,
          pressed && styles.dim,
        ]}
      >
        <Label aria-hidden style={styles.profileBlockGlyph}>
          🚫
        </Label>
      </Pressable>
    </View>
  );
}
export function Icon({
  name,
  label,
  onPress,
  selected,
}: {
  name: string;
  label: string;
  onPress: () => void;
  selected?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ selected: !!selected }}
      onPress={onPress}
      style={({ pressed }) => [styles.iconButton, pressed && styles.dim]}
    >
      <Image
        source={{ uri: `icon-${name}` }}
        style={[styles.icon, selected && styles.selectedIcon]}
        resizeMode="contain"
      />
    </Pressable>
  );
}
export function Field({ label, ...props }: TextInputProps & { label: string }) {
  return (
    <View style={styles.gap}>
      <Label muted>{label}</Label>
      <TextInput
        {...props}
        accessibilityLabel={label}
        placeholderTextColor={colors.secondary}
        selectionColor={colors.lime}
        style={[
          styles.field,
          props.multiline && { minHeight: 90 },
          props.style,
        ]}
      />
    </View>
  );
}
export function Card({ children }: PropsWithChildren) {
  return <View style={styles.card}>{children}</View>;
}
export function Photo({ uri, ratio = 1.9 }: { uri?: string; ratio?: number }) {
  return (
    <Image
      source={{ uri: uri || "icon-me" }}
      resizeMode="cover"
      style={[styles.photo, { aspectRatio: ratio }]}
    />
  );
}
export function Avatar({ uri, size = 50 }: { uri?: string; size?: number }) {
  return (
    <Image
      source={{ uri: uri || "icon-me" }}
      style={{
        width: size,
        height: size,
        borderRadius: size / 2,
        backgroundColor: colors.ink,
      }}
    />
  );
}
export function Page({
  title,
  actions,
  children,
  onRefresh,
}: PropsWithChildren<{
  title: string;
  actions?: React.ReactNode;
  onRefresh?: () => Promise<unknown>;
}>) {
  const app = useApp();
  const [refreshing, setRefreshing] = useState(false);
  const [notice, setNotice] = useState("");
  async function refresh() {
    setRefreshing(true);
    try {
      const result = await (onRefresh ? onRefresh() : app.command("refresh"));
      if (result !== undefined) setNotice("Updated");
    } finally {
      setRefreshing(false);
    }
  }
  return (
    <KeyboardAvoidingView style={styles.flex} behavior="padding">
      <View style={styles.header}>
        {app.canGoBack && <Icon name="back" label="Back" onPress={app.back} />}
        <Label title style={styles.flex}>
          {title}
        </Label>
        {actions}
      </View>
      <ScrollView
        contentContainerStyle={[
          styles.page,
          !app.canGoBack && { paddingBottom: 96 },
        ]}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={refresh}
            tintColor={colors.lime}
          />
        }
      >
        {notice && (
          <View accessibilityLiveRegion="polite">
            <Label muted>{notice}</Label>
          </View>
        )}
        {children}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
export function Tabs({
  values,
  selected,
  onSelect,
}: {
  values: string[];
  selected: string;
  onSelect: (value: string) => void;
}) {
  return (
    <View style={styles.row}>
      {values.map((value) => (
        <Pressable
          key={value}
          accessibilityRole="tab"
          accessibilityState={{ selected: value === selected }}
          onPress={() => onSelect(value)}
          style={[
            styles.collectionTab,
            value === selected && styles.collectionSelected,
          ]}
        >
          <Label
            style={{
              color: value === selected ? colors.lime : colors.secondary,
              textAlign: "center",
            }}
          >
            {value}
          </Label>
        </Pressable>
      ))}
    </View>
  );
}
export function confirm(
  title: string,
  message: string,
  action: string,
  perform: () => void,
  destructive = false,
) {
  Alert.alert(title, message, [
    { text: "Cancel", style: "cancel" },
    {
      text: action,
      style: destructive ? "destructive" : "default",
      onPress: perform,
    },
  ]);
}
export function choose(
  title: string,
  values: string[],
  action: (value: string) => void,
) {
  Alert.alert(title, undefined, [
    ...values.map((value) => ({ text: value, onPress: () => action(value) })),
    { text: "Cancel", style: "cancel" },
  ]);
}
export const styles = StyleSheet.create({
  flex: { flex: 1 },
  gap: { gap: 6 },
  row: { flexDirection: "row", alignItems: "center", gap: 8 },
  text: { color: colors.ivory, fontFamily: "ComicNeue-Regular", fontSize: 17 },
  muted: { color: colors.secondary },
  title: { fontFamily: "Kalam-Bold", fontSize: 28 },
  header: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 16,
    minHeight: 58,
    gap: 8,
  },
  page: { padding: 18, paddingBottom: 28, gap: 14, flexGrow: 1 },
  card: {
    backgroundColor: colors.panel,
    borderRadius: 20,
    padding: 14,
    gap: 10,
  },
  button: {
    minHeight: 44,
    borderRadius: 14,
    backgroundColor: colors.panel,
    paddingHorizontal: 14,
    paddingVertical: 10,
    alignItems: "center",
    justifyContent: "center",
  },
  buttonText: { fontFamily: "Kalam-Bold", textAlign: "center" },
  primary: { backgroundColor: colors.lime },
  dim: { opacity: 0.5 },
  profileActions: { flexDirection: "row", alignItems: "stretch", gap: 8 },
  profileActionButton: { flex: 1, minWidth: 0, paddingVertical: 4 },
  profileBlockButton: {
    width: 44,
    minHeight: 44,
    alignItems: "center",
    justifyContent: "center",
  },
  profileBlockSelected: { backgroundColor: colors.panel, borderRadius: 14 },
  profileBlockGlyph: { fontSize: 20 },
  iconButton: {
    width: 44,
    height: 44,
    alignItems: "center",
    justifyContent: "center",
  },
  icon: { width: 36, height: 36 },
  selectedIcon: {
    opacity: 1,
    shadowColor: colors.lime,
    shadowOpacity: 0.8,
    shadowRadius: 5,
  },
  field: {
    minHeight: 46,
    borderRadius: 14,
    backgroundColor: colors.panel,
    padding: 12,
    color: colors.ivory,
    fontFamily: "ComicNeue-Regular",
    fontSize: 17,
  },
  photo: { width: "100%", borderRadius: 16, backgroundColor: colors.ink },
  collectionTab: {
    flex: 1,
    minHeight: 44,
    justifyContent: "center",
    paddingVertical: 8,
    borderBottomWidth: 3,
    borderBottomColor: "transparent",
  },
  collectionSelected: { borderBottomColor: colors.lime },
});
