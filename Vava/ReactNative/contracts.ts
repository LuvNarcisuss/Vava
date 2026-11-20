export interface Person {
  id: string;
  name: string;
  isPublisher: boolean;
  code: string;
  following: boolean;
  blocked: boolean;
  restriction?: string;
}
export interface Publisher {
  id: string;
  name: string;
  avatar?: string;
  website?: string;
}
export interface Clip {
  id: string;
  title: string;
  detail: string;
  publisher: string;
  publisherID: string;
  source?: string;
  license: string;
  licenseURL?: string;
  media: string;
  cover: string;
  duration: number;
  submissionID?: string;
  engagement: { likes: number; saves: number; shares: number };
  editorialComments: { id: string; body: string }[];
}
export interface Course {
  id: string;
  title: string;
  category: string;
  level: string;
  detail: string;
  price: number;
  minutes: number;
  cover: string;
  steps?: string[];
  reference: string;
  referenceName: string;
  author: Publisher;
}
export interface Replay {
  id: string;
  title: string;
  event: string;
  publisher: string;
  source: string;
  cover: string;
}
export interface Profile {
  id: string;
  name: string;
  bio: string;
  avatarURI?: string;
}
export interface Comment {
  id: string;
  author: Profile;
  body: string;
  replyTo?: string;
  postedAt?: string;
}
export interface Message {
  id: string;
  text: string;
  date: string;
  kind: "incoming" | "sending" | "confirmed" | "unconfirmed" | "notice";
  awaiting: boolean;
}
export interface Conversation {
  person: Person;
  entries: Message[];
  inbox: { pinned: boolean; unread: boolean; hidden: boolean };
}
export interface Call {
  id: string;
  person: Person;
  video: boolean;
  phase: "ringing" | "incoming" | "connecting" | "connected" | "ended";
  detail: string;
}
export interface Snapshot {
  revision: number;
  signedIn: boolean;
  agreements: { revision: string; terms: string; privacy: string };
  catalog: { shorts: Clip[]; courses: Course[]; replays: Replay[] };
  state?: {
    me: Profile;
    likes: string[];
    saves: string[];
    hidden: string[];
    practice: Record<string, number[]>;
    following: string[];
    blocked: string[];
    commentsByClip: Record<string, Comment[]>;
    shareCounts: Record<string, number>;
  };
  ownedClips: Clip[];
  wallet?: {
    balance: number;
    owned: string[];
    entries: { id: string; title: string; amount: number; date: string }[];
    packs: { productID: string; coins: number; price?: string }[];
    busy: boolean;
    retrying: boolean;
    hasPurchaseIssue: boolean;
    paymentsAllowed: boolean;
    catalogStatus:
      | "idle"
      | "loading"
      | "ready"
      | "partial"
      | "unavailable"
      | "failed";
    catalogMessage: string;
  };
  chat: {
    players: Person[];
    histories: Conversation[];
    playerCode?: string;
    discoveryIssue?: string;
    call?: Call;
  };
}
export interface Response {
  snapshot: Snapshot;
  message?: string;
  avatarURI?: string;
}
