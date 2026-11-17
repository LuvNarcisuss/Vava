import React from "react";
import { createRoot } from "react-dom/client";
import App from "../ReactNative/WebApp";
import { ScreenBackground } from "../ReactNative/ScreenBackground";

class PageBoundary extends React.Component<
  React.PropsWithChildren,
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? (
      <main className="failure">
        <ScreenBackground />
        <div className="failure-content">
          <img
            src="art/brand-logo.png"
            alt="Vava logo"
            width={112}
            height={112}
            style={{ borderRadius: 22 }}
          />
          <p>This page could not be opened.</p>
          <button onClick={() => location.reload()}>Try again</button>
        </div>
      </main>
    ) : (
      this.props.children
    );
  }
}
createRoot(document.getElementById("root")!).render(
  <PageBoundary>
    <App />
  </PageBoundary>,
);
// Keep the composer above the onscreen keyboard, including modal forms.
function resize() {
  document.documentElement.style.setProperty(
    "--viewport-height",
    `${window.visualViewport?.height || window.innerHeight}px`,
  );
}
window.visualViewport?.addEventListener("resize", resize);
resize();
