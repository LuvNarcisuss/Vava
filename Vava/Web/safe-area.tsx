import React from "react";
import { View } from "react-native-web";
export const initialWindowMetrics = undefined;
export function SafeAreaProvider({ children }: any) {
  return children;
}
export function SafeAreaView({ children, style, ...props }: any) {
  return (
    <View
      {...props}
      style={[
        style,
        {
          paddingTop: "env(safe-area-inset-top)",
          paddingBottom: "env(safe-area-inset-bottom)",
          paddingLeft: "env(safe-area-inset-left)",
          paddingRight: "env(safe-area-inset-right)",
        },
      ]}
    >
      {children}
    </View>
  );
}
