import React, { createContext, useContext } from "react";
import { Person, Response, Snapshot } from "./native";

export interface Route {
  name: string;
  id?: string;
  person?: Person;
  collection?: string;
}
export interface AppState {
  snapshot: Snapshot;
  command: (
    name: string,
    payload?: Record<string, unknown>,
  ) => Promise<Response | undefined>;
  navigate: (route: Route) => void;
  back: () => void;
  canGoBack: boolean;
  active: boolean;
}
export const AppContext = createContext<AppState | undefined>(undefined);
export function useApp(): AppState {
  const context = useContext(AppContext);
  if (!context) throw new Error("Vava application context is unavailable.");
  return context;
}
