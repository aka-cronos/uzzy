// Landing copy for uzzy.app, simplified for v0.6.0 (issue #255) and aligned with GLOSSARY.md.
export const DOWNLOAD_URL =
  "https://github.com/aka-cronos/uzzy/releases/latest/download/Uzzy.dmg";
export const REPO_URL = "https://github.com/aka-cronos/uzzy";
export const MAKER = "akacronos";
export const X_URL = `https://x.com/${MAKER}`;
export const VERSION = "0.6.0";
export const REQUIREMENTS = "macOS 27 · Apple Silicon";

export const hero = {
  title: "Your AI tools have limits. Checking them shouldn’t be a task.",
  subtitle:
    "See what you’ve used, what’s left and when your usage limits reset for Claude, Codex, Cursor and Antigravity, right in your menu bar.",
};

export const features = [
  {
    title: "Every limit stays separate.",
    body: "Five-hour, weekly and per-model usage limits are never blended into one number. Each keeps its own bar, reset time and countdown.",
  },
  {
    title: "Refreshes only when you look.",
    body: "Uzzy checks when you open the panel and every five minutes while it stays open. Close it and requests stop, unless you turn on background refresh.",
  },
  {
    title: "Optional alerts, off by default.",
    body: "Turn on background refresh in Settings to get notified near your threshold, at 100%, or when a limit resets.",
  },
  {
    title: "Missing never means zero.",
    body: "If a session expires or a provider can’t be reached, Uzzy tells you why and keeps your last reading marked out of date.",
  },
];

export const providers = [
  {
    name: "Claude",
    session: "Claude Code",
    shows: "5-hour, weekly and per-model limits, resets available, usage credits and credit balances",
  },
  {
    name: "Codex",
    session: "Codex CLI · ChatGPT sign-in",
    shows: "5-hour, weekly and extra limits, resets available and credit balance",
  },
  {
    name: "Cursor",
    session: "Cursor",
    shows: "Unified or legacy plan limits (Cursor Models and Other Models) and credit balance",
  },
  {
    name: "Antigravity",
    session: "Antigravity",
    shows: "5-hour and weekly limits for Gemini, Claude and GPT, and any model group your plan keeps apart",
  },
];

export type SettingsTabId = "general" | "providers" | "notifications";

export const settingsTabs: {
  id: SettingsTabId;
  label: string;
  summary: string;
  image: string;
  width: number;
  height: number;
  alt: string;
  items: { title: string; body: string }[];
}[] = [
  {
    id: "general",
    label: "General",
    summary: "Display style for usage limits, reset countdowns, resets available, and update checks.",
    image: "/settings-general.png",
    width: 592,
    height: 672,
    alt: "Uzzy Settings, General tab: a Used / Left switch for the percentage on the cards, a Simple / Detailed switch for the time until a reset, a switch for resets available, a switch to check for updates, and the installed version at the bottom.",
    items: [
      {
        title: "Used or left.",
        body: "Show how much of each usage limit you’ve used, or how much is left.",
      },
      {
        title: "Resets & countdowns.",
        body: "Pick short (2 h) or detailed (2 h 28 min) countdowns, and show or hide resets available.",
      },
      {
        title: "Update checks.",
        body: "Checks GitHub once a day with no data about you. Turn it off anytime.",
      },
    ],
  },
  {
    id: "providers",
    label: "Providers",
    summary: "Choose which of Claude, Codex, Cursor and Antigravity are turned on, and set the card order.",
    image: "/settings-providers.png",
    width: 592,
    height: 487,
    alt: "Uzzy Settings, Providers tab: Claude, Codex, Cursor and Antigravity with buttons to reorder them and a switch to turn each one on or off.",
    items: [
      {
        title: "Only the tools you use.",
        body: "Turn off any provider you don’t use. It gets no card and Uzzy never reads its session.",
      },
      {
        title: "Your order.",
        body: "Move cards up or down so the provider you check most comes first.",
      },
      {
        title: "Cursor Keychain access.",
        body: "Revoke access to Cursor’s key anytime right from the Providers tab.",
      },
    ],
  },
  {
    id: "notifications",
    label: "Notifications",
    summary: "Optional background refresh and usage limit alerts, all turned off until you opt in.",
    image: "/settings-notifications.png",
    width: 592,
    height: 687,
    alt: "Uzzy Settings, Notifications tab: a switch and interval picker for background refresh, and alert switches for near a usage limit with threshold, when a limit is reached, and when a limit resets.",
    items: [
      {
        title: "Background refresh.",
        body: "Off by default. Check turned-on providers every 5, 10, 15 or 30 minutes while the panel is closed, reusing your last session with no Keychain prompts.",
      },
      {
        title: "Near a usage limit.",
        body: "Get notified once per window when any turned-on provider crosses the threshold you pick.",
      },
      {
        title: "Reached & reset.",
        body: "Get notified when a limit hits 100% used (0% left), and again when it resets.",
      },
    ],
  },
];

export const privacy = [
  {
    title: "Read-only sessions.",
    body: "Uzzy never asks for passwords, signs in for you or writes credentials. Cursor’s encrypted session is read only after you allow Keychain access.",
  },
  {
    title: "Straight to your providers.",
    body: "Requests go directly to your providers, plus GitHub once a day for updates if enabled. No Uzzy server. No telemetry.",
  },
  {
    title: "In memory only.",
    body: "Usage readings are never saved to disk.",
  },
];

export const hosts = [
  "api.anthropic.com",
  "chatgpt.com",
  "api2.cursor.sh",
  "daily-cloudcode-pa.sandbox.googleapis.com",
  "127.0.0.1",
  "api.github.com",
];

export const faqs = [
  {
    question: "Do I need all four tools?",
    answer:
      "No, one is enough. Turn off the rest in Settings: their cards disappear and Uzzy won’t read their sessions.",
  },
  {
    question: "How do I update Uzzy?",
    answer:
      "Uzzy doesn’t auto-update. When a new version is out, an Update button appears in the panel to download the new Uzzy.dmg.",
  },
  {
    question: "Does background refresh trigger Keychain prompts?",
    answer:
      "No. Background checks reuse the session from the last time you opened the panel. If a session expires, checks pause until you open the panel again.",
  },
];

export const disclaimer =
  "Uzzy is an independent project, not affiliated with, endorsed or sponsored by Anthropic, OpenAI, Anysphere or Google. It reads usage limits through undocumented endpoints that may change without notice.";
