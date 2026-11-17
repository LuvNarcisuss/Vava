import React, { forwardRef, useRef } from "react";
import * as Web from "react-native-web";
export * from "react-native-web";

// Browser dialogs preserve all native alert choices, including destructive confirmations.
export const Alert = {
  alert(
    title: string,
    message?: string,
    buttons = [{ text: "OK" }] as {
      text?: string;
      style?: string;
      onPress?: () => void;
    }[],
  ) {
    const previous = document.activeElement as HTMLElement | null;
    const overlay = document.createElement("dialog");
    overlay.className = "vava-dialog";
    const heading = document.createElement("h2");
    heading.textContent = title;
    overlay.append(heading);
    if (message) {
      const body = document.createElement("p");
      body.textContent = message;
      overlay.append(body);
    }
    function close() {
      overlay.close();
      overlay.remove();
      previous?.focus();
    }
    buttons.forEach((item) => {
      const button = document.createElement("button");
      button.textContent = item.text || "OK";
      if (item.style === "destructive") button.className = "danger";
      button.onclick = () => {
        close();
        item.onPress?.();
      };
      overlay.append(button);
    });
    overlay.addEventListener("cancel", () => {
      close();
      buttons.find((item) => item.style === "cancel")?.onPress?.();
    });
    document.body.append(overlay);
    overlay.showModal();
  },
};
function source(value: any): any {
  if (Array.isArray(value)) return value.map(source);
  if (
    value &&
    typeof value.uri === "string" &&
    /^(icon-[a-z-]+|background|welcome|brand-logo)$/.test(value.uri)
  )
    return { ...value, uri: `art/${value.uri}.png` };
  return value;
}
export const Image = forwardRef<any, any>((props, ref) => (
  <Web.Image {...props} source={source(props.source)} ref={ref} />
));

// ScrollView handles the gesture. The indicator appears only during the request.
export function RefreshControl({ refreshing }: { refreshing: boolean }) {
  return refreshing ? (
    <span className="vava-refresh-status" role="status">
      Refreshing…
    </span>
  ) : null;
}
export const ScrollView = forwardRef<any, any>(
  ({ refreshControl, onTouchStart, onTouchEnd, onTouchCancel, ...props }, ref) => {
    const start = useRef<{ id: number; x: number; y: number } | null>(null);
    return (
      <Web.ScrollView
        {...props}
        ref={ref}
        onTouchStart={(event: React.TouchEvent<HTMLElement>) => {
          onTouchStart?.(event);
          const touches = event.nativeEvent.touches;
          const touch = touches[0];
          const target = event.target;
          const editing =
            target instanceof Element &&
            target.closest("input, textarea, select, [contenteditable='true']");
          start.current =
            refreshControl &&
            !refreshControl.props.refreshing &&
            !props.horizontal &&
            event.currentTarget.scrollTop <= 0 &&
            touches.length === 1 &&
            !editing
              ? { id: touch.identifier, x: touch.clientX, y: touch.clientY }
              : null;
        }}
        onTouchEnd={(event: React.TouchEvent<HTMLElement>) => {
          onTouchEnd?.(event);
          const origin = start.current;
          start.current = null;
          const touch = event.nativeEvent.changedTouches[0];
          if (
            origin &&
            touch?.identifier === origin.id &&
            event.nativeEvent.touches.length === 0 &&
            event.currentTarget.scrollTop <= 0 &&
            touch.clientY - origin.y > 85 &&
            Math.abs(touch.clientX - origin.x) < 45 &&
            refreshControl &&
            !refreshControl.props.refreshing
          )
            refreshControl.props.onRefresh?.();
        }}
        onTouchCancel={(event: React.TouchEvent<HTMLElement>) => {
          start.current = null;
          onTouchCancel?.(event);
        }}
      >
        {refreshControl}
        {props.children}
      </Web.ScrollView>
    );
  },
);

export const FlatList = forwardRef<any, any>((props, ref) => (
  <Web.FlatList
    {...props}
    data={props.data}
    renderItem={props.renderItem}
    ref={ref}
    renderScrollComponent={(scrollProps: any) => (
      <ScrollView {...scrollProps} />
    )}
  />
));
