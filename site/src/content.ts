// Landing copy for uzzy.app, simplified for v0.6.0 (issue #255) and aligned with GLOSSARY.md.
export const DOWNLOAD_URL =
  "https://github.com/aka-cronos/uzzy/releases/latest/download/Uzzy.dmg";
export const REPO_URL = "https://github.com/aka-cronos/uzzy";
export const MAKER = "akacronos";
export const X_URL = `https://x.com/${MAKER}`;
export const VERSION = "0.6.0";
export const REQUIREMENTS = "macOS 27 · Apple Silicon";

export const hero = {
  title: "Your AI tools have limits. Checking them shouldn’t be a task",
  subtitle:
    "See what you’ve used, what’s left and when your usage limits reset for Claude, Codex, Cursor and Antigravity, right in your menu bar.",
};

export const features = [
  {
    title: "Every limit stays separate",
    body: "Five-hour, weekly and per-model usage limits are never blended into one number. Each keeps its own bar, reset time and countdown.",
    images: ["/cover/panel.png"],
    imageAlt: "The Uzzy panel showing Claude and Codex with separate 5-hour and Weekly usage limits, progress bars and reset countdowns.",
    kind: "popover" as const,
    popoverWidth: 408,
    popoverTop: "top-[calc(100%-17px)]",
    cropPosition: "object-left-top",
  },
  {
    title: "Missing never means zero",
    body: "If a session expires or a provider can’t be reached, Uzzy explains why and keeps your last reading marked out of date.",
    images: ["/features/stale.png"],
    imageAlt: "The Uzzy panel when offline: shows the error message and marks the last valid readings (35% and 62% used) as out of date.",
    kind: "popover" as const,
    popoverWidth: 432,
    popoverTop: "top-[calc(100%-18px)]",
    cropPosition: "object-right-bottom",
  },
  {
    title: "Quiet until you look. Alerts on your terms",
    body: "Refreshes only while the panel is open. Turn on background refresh in Settings to get notified near your threshold, at 100%, or on reset.",
    images: [
      "/features/notif-near.png",
      "/features/notif-reached.png",
      "/features/notif-reset.png",
    ],
    imageAlt: "macOS notifications from Uzzy: 85% used on Claude (5-hour), Codex (5-hour) limit reached, and Claude ready to use again after reset.",
    kind: "notifications" as const,
    popoverWidth: undefined,
    popoverTop: undefined,
    cropPosition: "object-center",
  },
];

export const providers = [
  {
    name: "Claude",
    hosts: ["api.anthropic.com"],
    shows: "Per-model weekly limits, resets available, usage credits and cloud session credits",
  },
  {
    name: "Codex",
    hosts: ["chatgpt.com"],
    shows: "ChatGPT sign-in via Codex CLI, extra limits, resets available and credit balance",
  },
  {
    name: "Cursor",
    hosts: ["api2.cursor.sh"],
    shows: "Unified weekly plans, legacy Cursor Models and Other Models, and credit balance",
  },
  {
    name: "Antigravity",
    hosts: ["daily-cloudcode-pa.sandbox.googleapis.com", "127.0.0.1"],
    shows: "Gemini, Claude and GPT, plus any model group your plan keeps apart",
  },
];

export type SettingsTabId = "general" | "providers" | "notifications";

export const settingsTabs: {
  id: SettingsTabId;
  label: string;
  image: string;
  width: number;
  height: number;
  alt: string;
  items: { title: string; body: string }[];
}[] = [
  {
    id: "general",
    label: "General",
    image: "/settings-general.png",
    width: 592,
    height: 672,
    alt: "Uzzy Settings, General tab: a Used / Left switch for the percentage on the cards, a Simple / Detailed switch for the time until a reset, a switch for resets available, a switch to check for updates, and the installed version at the bottom.",
    items: [
      {
        title: "Used or left",
        body: "Show how much of each usage limit you’ve used, or how much is left.",
      },
      {
        title: "Resets & countdowns",
        body: "Pick short (2 h) or detailed (2 h 28 min) countdowns, and turn resets available on or off.",
      },
      {
        title: "Update checks",
        body: "Checks GitHub once a day for new releases with no data about you. Turn it off anytime.",
      },
    ],
  },
  {
    id: "providers",
    label: "Providers",
    image: "/settings-providers.png",
    width: 592,
    height: 540,
    alt: "Uzzy Settings, Providers tab: Claude, Codex, Cursor with Keychain access revoke control, and Antigravity with buttons to reorder them and a switch to turn each one on or off.",
    items: [
      {
        title: "Only the tools you use",
        body: "Use one, two or all four. Turned-off providers get no card and Uzzy never reads their sessions.",
      },
      {
        title: "Your order",
        body: "Move cards up or down so the providers you check most always stay at the top.",
      },
      {
        title: "Cursor Keychain access",
        body: "Cursor’s session is read only after you allow it, and you can revoke access here anytime.",
      },
    ],
  },
  {
    id: "notifications",
    label: "Notifications",
    image: "/settings-notifications.png",
    width: 592,
    height: 687,
    alt: "Uzzy Settings, Notifications tab: a switch and interval picker for background refresh, and alert switches for near a usage limit with threshold, when a limit is reached, and when a limit resets.",
    items: [
      {
        title: "Background refresh",
        body: "Off by default. Check every 5 to 30 minutes while closed, with no extra Keychain prompts.",
      },
      {
        title: "Near a usage limit",
        body: "Get notified once per window when any turned-on provider crosses the threshold you pick.",
      },
      {
        title: "Reached & reset",
        body: "Get notified when a limit hits 100% used (0% left), and again when it resets.",
      },
    ],
  },
];

export const privacy = [
  {
    title: "Read-only sessions",
    body: "Uzzy never asks for passwords, signs in for you or writes credentials. Cursor’s encrypted session is read only after you allow Keychain access.",
  },
  {
    title: "Straight to your providers",
    body: "Requests go directly to your providers, plus GitHub once a day for updates if enabled. No Uzzy server. No telemetry.",
  },
  {
    title: "In memory only",
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
    question: "Where do the numbers come from?",
    answer:
      "Uzzy reads the local sessions on your Mac in read-only mode and calls the same endpoints the official apps use. Usage percentages and reset times come straight from each provider, never estimated or scraped.",
  },
  {
    question: "Can it alert me before I reach a usage limit?",
    answer:
      "Yes. Background refresh and notifications are turned off by default. Turn them on in Settings to get notified near your threshold, at 100% used, or when a limit resets, with no extra Keychain prompts.",
  },
  {
    question: "Does Uzzy save anything to disk or track me?",
    answer:
      "No. Usage readings stay in memory only and are never written to disk. Only your preferences are saved locally. There is no Uzzy server and no telemetry.",
  },
  {
    question: "What happens if a provider changes its endpoint?",
    answer:
      "Because Uzzy uses undocumented endpoints, a provider can change them without notice. When that happens, Uzzy explains the error and keeps your last reading marked out of date instead of showing 0%. I work on a fix as soon as possible and ship an update once one is found.",
  },
  {
    question: "How do I update Uzzy?",
    answer:
      "Uzzy doesn’t auto-update. If update checks are turned on in Settings, it checks GitHub once a day and shows an Update button in the panel when a new Uzzy.dmg is out.",
  },
];

export const disclaimer =
  "Uzzy is an independent project, not affiliated with, endorsed or sponsored by Anthropic, OpenAI, Anysphere or Google. It reads usage limits through undocumented endpoints that may change without notice.";
