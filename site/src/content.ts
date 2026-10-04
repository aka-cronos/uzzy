// The landing copy, approved in issue #144.
export const DOWNLOAD_URL =
  "https://github.com/aka-cronos/uzzy/releases/latest/download/Uzzy.dmg";
export const REPO_URL = "https://github.com/aka-cronos/uzzy";
export const MAKER = "akacronos";
export const X_URL = `https://x.com/${MAKER}`;
export const VERSION = "0.2.0";
export const REQUIREMENTS = "macOS 27 · Apple Silicon";

export const hero = {
  title: "Your AI tools have limits. Checking them shouldn’t be a task.",
  subtitle: "See how much you’ve used, how much is left and when your usage limits reset—for Claude, Codex and Cursor, in one menu bar panel.",
};

export const why = "Keep using Claude, Codex and Cursor. Uzzy brings their usage limits together so you can stop checking each one separately.";

export const features = [
  { title: "Three tools. One quick check.", body: "Open Uzzy from your menu bar to see Claude, Codex and Cursor together, with a separate card for each provider and its plan." },
  { title: "Different limits stay different.", body: "Check each usage limit on its own, with its reset time, countdown and last reading. Five-hour and weekly limits are never blended into one number." },
  { title: "Checks while you look.", body: "Uzzy refreshes readings when needed as you open the panel, then every five minutes while it stays open. Close it and the requests stop." },
  { title: "Missing doesn’t mean zero.", body: "If a session expires or a provider can’t be reached, Uzzy tells you what happened. The other providers keep working." },
];

export const providers = [
  {
    name: "Claude",
    session: "Claude Code",
    shows: "5 hours, weekly, weekly per model, usage credits this month",
  },
  {
    name: "Codex",
    session: "Codex CLI (ChatGPT sign-in)",
    shows: "5 hours, weekly, extra limits, banked resets",
  },
  {
    name: "Cursor",
    session: "Cursor",
    shows: "Cursor Models and Other Models for the billing cycle",
  },
];

export const settings = [
  { title: "Used or left.", body: "Choose whether the cards show how much of each usage limit you’ve used or how much is left." },
  { title: "Only the tools you use.", body: "Turn off the providers you don’t use. They get no card, and Uzzy doesn’t read their session or query their usage limits." },
  { title: "Your order.", body: "Move the cards up or down so the provider you check most comes first." },
];

export const privacy = [
  { title: "Read-only access.", body: "Uzzy reuses your existing sessions. It never asks for a password, signs in for you or writes credentials." },
  { title: "Straight to your providers.", body: "Usage requests go directly to Claude, Codex and Cursor. Once a day Uzzy asks GitHub for the latest version, unless you turn that off. No telemetry. No server of its own." },
  { title: "Readings stay in memory.", body: "Uzzy doesn’t save usage readings to disk." },
];

export const hosts = ["api.anthropic.com", "chatgpt.com", "api2.cursor.sh", "api.github.com"];

export const disclaimer = "Uzzy is an independent project, not affiliated with, endorsed or sponsored by Anthropic, OpenAI or Anysphere. It reads usage limits through undocumented endpoints that may change without notice.";
