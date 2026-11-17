import React from "react";
import { Image, StyleSheet, View } from "react-native";

export function ScreenBackground() {
  return (
    <View
      aria-hidden
      pointerEvents="none"
      testID="vava-screen-background"
      style={[StyleSheet.absoluteFill, styles.surface]}
    >
      <Image
        source={{ uri: "background" }}
        resizeMode="cover"
        style={[StyleSheet.absoluteFill, styles.artwork]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  surface: { backgroundColor: "#0D211F" },
  artwork: { opacity: 0.8 },
});
