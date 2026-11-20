import React, { useEffect, useRef, useState } from "react";
import { StyleSheet, View } from "react-native-web";
export * from "../ReactNative/contracts";
export { request, subscribe } from "./bridge";

export function NativeVideo({
  uri,
  poster,
  paused,
  seekFraction,
  style,
  onProgress,
  onError,
}: any) {
  const video = useRef<HTMLVideoElement>(null);
  useEffect(() => {
    const element = video.current;
    if (!element) return;
    function sync() {
      if (paused || document.hidden) element!.pause();
      else
        void element!
          .play()
          .catch(() =>
            onError?.({ nativeEvent: { message: "Tap to play this video." } }),
          );
    }
    sync();
    document.addEventListener("visibilitychange", sync);
    window.addEventListener("vava-playback", sync);
    return () => {
      element.pause();
      document.removeEventListener("visibilitychange", sync);
      window.removeEventListener("vava-playback", sync);
    };
  }, [uri, paused]);
  useEffect(() => {
    const element = video.current;
    if (
      element &&
      seekFraction !== undefined &&
      Number.isFinite(element.duration)
    )
      element.currentTime =
        Math.max(0, Math.min(1, seekFraction)) * element.duration;
  }, [seekFraction]);
  return (
    <View style={style} pointerEvents="none">
      <video
        ref={video}
        src={uri}
        poster={poster}
        playsInline
        loop
        preload="metadata"
        style={{
          position: "absolute",
          inset: 0,
          width: "100%",
          height: "100%",
          objectFit: "contain",
        }}
        onTimeUpdate={(event) => {
          const v = event.currentTarget;
          if (Number.isFinite(v.duration))
            onProgress?.({
              nativeEvent: { currentTime: v.currentTime, duration: v.duration },
            });
        }}
        onError={() =>
          onError?.({
            nativeEvent: { message: "This video could not be played." },
          })
        }
      />
      <div className="vava-short-video-shade" aria-hidden="true" />
    </View>
  );
}
export function NativeCallVideo({ style, accessibilityLabel, localPreview }: any) {
  const [frame, setFrame] = useState<string>();
  useEffect(() => {
    const name = localPreview ? "vava-call-preview-frame" : "vava-call-frame";
    const receive = ((event: CustomEvent) =>
      setFrame(event.detail)) as EventListener;
    const clear = () => setFrame(undefined);
    window.addEventListener(name, receive);
    if (localPreview) window.addEventListener("vava-playback", clear);
    return () => {
      window.removeEventListener(name, receive);
      if (localPreview) window.removeEventListener("vava-playback", clear);
    };
  }, [localPreview]);
  return (
    <View style={style}>
      {frame && (
        <img
          src={frame}
          alt={accessibilityLabel || "Remote video"}
          style={{
            width: "100%",
            height: "100%",
            objectFit: "contain",
            transform: localPreview ? "scaleX(-1)" : undefined,
          }}
        />
      )}
    </View>
  );
}
