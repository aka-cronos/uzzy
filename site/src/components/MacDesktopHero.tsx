import { useEffect, useState } from "react";
import * as c from "@/content";
import { MENU_BAR } from "@/lib/marks";
import { DownloadButton } from "@/components/DownloadButton";

const LOGOS: Record<string, string> = {
  Claude: "/cover/claude.svg",
  Codex: "/cover/codex.svg",
  Cursor: "/cover/cursor.svg",
  Antigravity: "/cover/antigravity.svg",
};

const FINDER_MENUS = ["File", "Edit", "View", "Go", "Window", "Help"] as const;

const PANEL_IMG = {
  src: "/cover/panel.png",
  width: 408,
  height: 991,
  alt: "The Uzzy panel: cards for Claude, Codex, Cursor and Antigravity with their plans, each usage limit with its bar, used percentage and reset time.",
} as const;

function formatMacClock(date: Date): { date: string; time: string } {
  const weekday = new Intl.DateTimeFormat("en-GB", { weekday: "short" }).format(date);
  const month = new Intl.DateTimeFormat("en-GB", { month: "short" }).format(date);
  const time = new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  }).format(date);
  return { date: `${weekday} ${date.getDate()} ${month}`, time };
}

function HeroCopy({ tone }: { tone: "light" | "dark" }) {
  const isDark = tone === "dark";
  return (
    <div
      className={`flex max-w-[56ch] flex-col gap-6 lg:gap-7 ${
        !isDark ? "mx-auto items-center text-center" : ""
      }`}
    >
      <div className="rise flex flex-col gap-4">
        <h1
          className={`text-4xl leading-[1.08] font-semibold tracking-tight text-balance sm:text-5xl lg:text-[54px] ${
            isDark ? "text-slate-50" : "text-slate-900"
          }`}
        >
          {c.hero.title}
        </h1>
        <p
          className={`text-lg leading-relaxed text-pretty ${
            isDark ? "text-slate-300" : "text-slate-600"
          }`}
        >
          {c.hero.subtitle}
        </p>
      </div>

      <ul
        className={`rise flex flex-wrap gap-2.5 [--i:1] ${!isDark ? "justify-center" : ""}`}
        aria-label="Supported providers"
      >
        {c.providers.map((p) => (
          <li
            key={p.name}
            className={`flex items-center gap-2 rounded-full border px-3.5 py-1 text-sm font-medium ${
              isDark
                ? "border-white/15 bg-white/[0.08] text-slate-100 backdrop-blur-xs"
                : "border-slate-300 bg-slate-100 text-slate-700"
            }`}
          >
            <img
              src={LOGOS[p.name]}
              alt=""
              width={16}
              height={p.name === "Cursor" ? 18 : 16}
              className={!isDark && p.name !== "Claude" ? "invert" : undefined}
            />
            {p.name}
          </li>
        ))}
      </ul>

      <div className={`rise flex flex-col gap-3 [--i:2] ${!isDark ? "items-center" : ""}`}>
        <div
          className={`flex flex-wrap items-center gap-x-6 gap-y-3 ${
            !isDark ? "justify-center" : ""
          }`}
        >
          <DownloadButton variant={isDark ? "inverse" : "default"} />
          <a
            href={c.REPO_URL}
            className={`inline-flex min-h-11 items-center rounded font-medium underline-offset-4 transition-colors duration-200 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 ${
              isDark
                ? "text-slate-300 hover:text-white focus-visible:outline-white"
                : "text-slate-600 hover:text-slate-900 focus-visible:outline-slate-900"
            }`}
          >
            View on GitHub
          </a>
        </div>
        <p className={`text-sm text-pretty ${isDark ? "text-slate-400" : "text-slate-600"}`}>
          Free and open source · Version {c.VERSION} · {c.REQUIREMENTS}
        </p>
      </div>
    </div>
  );
}

export function MacDesktopHero() {
  const [isOpen, setIsOpen] = useState(false);
  const [clock, setClock] = useState<{ date: string; time: string } | null>(null);

  useEffect(() => {
    const tick = () => setClock(formatMacClock(new Date()));
    tick();
    const clockTimer = window.setInterval(tick, 15_000);
    const openTimer = window.setTimeout(() => setIsOpen(true), 180);
    return () => {
      window.clearInterval(clockTimer);
      window.clearTimeout(openTimer);
    };
  }, []);

  const panelMotion =
    "origin-top transition-[opacity,translate,scale] duration-300 ease-out-strong motion-reduce:transition-opacity motion-reduce:translate-y-0 motion-reduce:scale-100";

  return (
    <section className="pt-[88px] pb-12 lg:px-5 lg:pb-16">
      {/* Tablet & mobile (< lg): centered copy on the light canvas above the compact Mac frame */}
      <div className="mx-auto max-w-[1440px] px-6 pt-6 pb-10 sm:px-10 lg:hidden">
        <HeroCopy tone="light" />
      </div>

      <div className="px-3 sm:px-5 lg:px-0">
        <div className="relative mx-auto h-[480px] max-w-[1600px] overflow-hidden rounded-2xl bg-slate-950 text-slate-50 shadow-[0_30px_60px_-20px_rgb(15_23_42/0.35)] ring-1 ring-slate-900/10 sm:h-[560px] lg:flex lg:h-[clamp(660px,calc(100vh-104px),1040px)] lg:flex-col">
          <img
            src="/cover/bg.jpg"
            alt=""
            className="absolute inset-0 size-full object-cover"
            loading="eager"
          />

          {/* Menu bar: full macOS bar (Finder left, Uzzy + clock top-right) from sm+; centered Uzzy pill only on narrow phones */}
          <div className="relative z-20 grid grid-cols-[1fr_auto_1fr] items-center px-4 py-1.5 text-[13px] font-medium text-slate-50 select-none sm:flex sm:justify-between sm:px-5">
            <div className="hidden items-center gap-4 sm:flex" aria-hidden="true">
              <span className="text-[15px] leading-none"></span>
              <span className="font-semibold">Finder</span>
              {FINDER_MENUS.map((item) => (
                <span key={item} className="hidden text-slate-50/90 md:inline">
                  {item}
                </span>
              ))}
            </div>

            <div className="relative col-start-2 sm:hidden">
              <button
                type="button"
                onClick={() => setIsOpen((open) => !open)}
                aria-expanded={isOpen}
                aria-label={isOpen ? "Close Uzzy panel" : "Open Uzzy panel"}
                className={`flex cursor-pointer items-center rounded-full px-[9px] py-1 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white ${
                  isOpen ? "bg-[#323234]" : "hover:bg-white/15"
                }`}
              >
                <svg
                  className="-my-0.5 size-[18px]"
                  viewBox="0 0 32 32"
                  fill="currentColor"
                  aria-hidden="true"
                >
                  <path d={MENU_BAR} />
                </svg>
              </button>

              <img
                {...PANEL_IMG}
                aria-hidden={!isOpen}
                className={`pointer-events-none absolute top-[calc(100%-17px)] left-1/2 h-auto w-[min(408px,calc(100vw-40px))] max-w-none -translate-x-1/2 ${panelMotion} ${
                  isOpen
                    ? "translate-y-0 scale-100 opacity-100"
                    : "-translate-y-1.5 scale-[0.97] opacity-0"
                }`}
              />
            </div>

            <div className="flex items-center pl-1 whitespace-nowrap sm:pl-0">
              <div className="relative hidden sm:block">
                <button
                  type="button"
                  onClick={() => setIsOpen((open) => !open)}
                  aria-expanded={isOpen}
                  aria-controls="uzzy-hero-panel"
                  aria-label={isOpen ? "Close Uzzy panel" : "Open Uzzy panel"}
                  title={isOpen ? "Close Uzzy" : "Open Uzzy"}
                  className={`flex cursor-pointer items-center rounded-full px-[9px] py-1 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white ${
                    isOpen ? "bg-[#323234]" : "hover:bg-white/15"
                  }`}
                >
                  <svg
                    className="-my-0.5 size-[18px]"
                    viewBox="0 0 32 32"
                    fill="currentColor"
                    aria-hidden="true"
                  >
                    <path d={MENU_BAR} />
                  </svg>
                </button>

                <img
                  id="uzzy-hero-panel"
                  {...PANEL_IMG}
                  aria-hidden={!isOpen}
                  className={`pointer-events-none absolute top-[calc(100%-17px)] left-1/2 max-w-none -translate-x-1/2 ${panelMotion} ${
                    isOpen
                      ? "translate-y-0 scale-100 opacity-100"
                      : "-translate-y-1.5 scale-[0.97] opacity-0"
                  }`}
                />
              </div>

              <img
                src="/cover/wifi.svg"
                alt=""
                width="34.5"
                height="20"
                aria-hidden="true"
                className="hidden shrink-0 sm:block"
              />
              <img
                src="/cover/control-center.svg"
                alt=""
                width="31.15"
                height="21.41"
                aria-hidden="true"
                className="hidden shrink-0 sm:block"
              />
              <time
                aria-hidden="true"
                className="hidden gap-2 pl-[9px] font-semibold tabular-nums sm:flex"
              >
                <span>{clock?.date ?? "Thu 24 Sep"}</span>
                <span>{clock?.time ?? "9:00 AM"}</span>
              </time>
            </div>
          </div>

          {/* Desktop (lg+): copy vertically centered inside the dark Mac frame, aligned to the 1440px header rail */}
          <div className="relative z-10 hidden flex-1 px-7 lg:flex">
            <div className="mx-auto grid w-full max-w-[1344px] flex-1 grid-cols-[minmax(0,1fr)_440px] items-center gap-12 py-10">
              <HeroCopy tone="dark" />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
