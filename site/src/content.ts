// The landing copy, from the README and issue #105.
export const DOWNLOAD_URL =
  "https://github.com/aka-cronos/uzzy/releases/latest/download/Uzzy.dmg";
export const REPO_URL = "https://github.com/aka-cronos/uzzy";
export const VERSION = "0.1.0";
export const REQUIREMENTS = "macOS 27 · Apple Silicon";

export const hero = {
  title: "Your AI subscription quotas, in your menu bar.",
  subtitle:
    "How much you have used, how much is left and when each quota resets, for Claude, Codex and Cursor.",
};

export const why =
  "If you pay for more than one AI coding subscription, finding out how close you are to a limit means opening each provider's dashboard. Uzzy puts every quota in one panel, reusing the sessions Claude Code, Codex CLI and Cursor already keep on your Mac. Nothing to sign in to, no API key to paste.";

export const features = [
  {
    title: "One panel, every provider",
    body: "A menu bar icon opens a panel with a card for each subscription, and each card shows the account's plan next to its name.",
  },
  {
    title: "Every quota on its own",
    body: "5 hours, weekly, per model, usage credits: each quota gets its own bar, its reset in local time with a countdown, and when it was last read. Never blended into one number.",
  },
  {
    title: "Only asks while you look",
    body: "Uzzy reads your quotas when you open the panel and every five minutes while it stays open. Closed, it makes no requests at all.",
  },
  {
    title: "Honest when things fail",
    body: "No session, expired session, offline: the card says why and the others keep working. Missing data is never shown as zero.",
  },
];

export const providers = [
  {
    name: "Claude",
    session: "Claude Code",
    quotas: "5 hours, weekly, weekly per model, usage credits this month",
  },
  {
    name: "Codex",
    session: "Codex CLI (ChatGPT sign-in)",
    quotas: "5 hours, weekly, extra limits, banked resets",
  },
  {
    name: "Cursor",
    session: "Cursor",
    quotas: "Cursor Models and Other Models for the billing cycle",
  },
];

export const privacy = [
  "Reuses your existing sessions read-only. Never asks for a password, never signs in, never writes credentials.",
  "Talks only to api.anthropic.com, chatgpt.com and api2.cursor.sh. No telemetry, no server of its own.",
  "Quotas live in memory only. Nothing is written to disk.",
];
export const hosts = ["api.anthropic.com", "chatgpt.com", "api2.cursor.sh"];

export const disclaimer =
  "Uzzy is an independent project, not affiliated with, endorsed or sponsored by Anthropic, OpenAI or Anysphere. It reads quotas through undocumented endpoints that may change without notice.";
