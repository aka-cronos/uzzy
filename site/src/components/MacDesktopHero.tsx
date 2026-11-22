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
    "origin-top transition-[opacity,transform] duration-300 ease-out-strong motion-reduce:transition-opacity motion-reduce:transform-none";

  return (
    <section className="px-3 pt-[84px] pb-12 sm:px-5 sm:pt-[88px] lg:pb-16">
      <div className="relative overflow-hidden rounded-2xl bg-slate-950 text-slate-50 shadow-[0_30px_60px_-20px_rgb(15_23_42/0.35)] ring-1 ring-slate-900/10 lg:flex lg:h-[clamp(660px,calc(100vh-104px),1040px)] lg:flex-col">
        <img
          src="/cover/bg.jpg"
          alt=""
          className="absolute inset-0 size-full object-cover"
          loading="eager"
        />

        {/* Transparent macOS menu bar across the full desktop frame */}
        <div className="relative z-20 flex items-center justify-between px-4 py-1.5 text-[13px] font-medium text-slate-50 select-none sm:px-5">
          <div className="flex items-center gap-4" aria-hidden="true">
            <span className="text-[15px] leading-none"></span>
            <span className="font-semibold">Finder</span>
            {FINDER_MENUS.map((item) => (
              <span key={item} className="hidden text-slate-50/90 md:inline">
                {item}
              </span>
            ))}
          </div>

          <div className="flex items-center">
            <div className="relative">
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
                className={`pointer-events-none absolute top-[calc(100%-17px)] left-1/2 hidden max-w-none -translate-x-1/2 lg:block ${panelMotion} ${
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
              className="hidden sm:block"
            />
            <img
              src="/cover/control-center.svg"
              alt=""
              width="31.15"
              height="21.41"
              aria-hidden="true"
              className="hidden sm:block"
            />
            <time
              aria-hidden="true"
              className="flex gap-2 pl-2 font-semibold tabular-nums sm:pl-[9px]"
            >
              <span>{clock?.date ?? "Thu 24 Sep"}</span>
              <span>{clock?.time ?? "9:00 AM"}</span>
            </time>
          </div>
        </div>

        {/* Content aligned to the header's left rail: outer px (12/20/20) + inner px (12/20/28) = header px (24/40/48), max-w 1344 = 1440 - 96 */}
        <div className="relative z-10 flex flex-1 px-3 sm:px-5 lg:px-7">
          <div className="mx-auto flex w-full max-w-[1344px] flex-1 flex-col justify-center gap-10 pt-10 pb-8 lg:grid lg:grid-cols-[minmax(0,1fr)_440px] lg:items-center lg:gap-12 lg:py-10">
            <div className="flex max-w-[56ch] flex-col gap-7">
              <div className="rise flex flex-col gap-4">
                <h1 className="text-4xl leading-[1.08] font-semibold tracking-tight text-pretty text-slate-50 sm:text-5xl lg:text-[54px]">
                  {c.hero.title}
                </h1>
                <p className="text-lg leading-relaxed text-pretty text-slate-300">
                  {c.hero.subtitle}
                </p>
              </div>

              <ul className="rise flex flex-wrap gap-2.5 [--i:1]" aria-label="Supported providers">
                {c.providers.map((p) => (
                  <li
                    key={p.name}
                    className="flex items-center gap-2 rounded-full border border-white/15 bg-white/[0.08] px-3.5 py-1 text-sm font-medium text-slate-100 backdrop-blur-xs"
                  >
                    <img
                      src={LOGOS[p.name]}
                      alt=""
                      width={16}
                      height={p.name === "Cursor" ? 18 : 16}
                    />
                    {p.name}
                  </li>
                ))}
              </ul>

              <div className="rise flex flex-col gap-3 [--i:2]">
                <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
                  <DownloadButton variant="inverse" />
                  <a
                    href={c.REPO_URL}
                    className="inline-flex min-h-11 items-center rounded font-medium text-slate-300 underline-offset-4 transition-colors duration-200 hover:text-white hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white"
                  >
                    View on GitHub
                  </a>
                </div>
                <p className="text-sm text-slate-400 text-pretty">
                  Free and open source · Version {c.VERSION} · {c.REQUIREMENTS}
                </p>
              </div>
            </div>

            {/* Mobile / tablet collapsible panel using grid-rows transition */}
            <div
              className={`grid transition-[grid-template-rows,opacity] duration-300 ease-out-strong lg:hidden ${
                isOpen ? "grid-rows-[1fr] opacity-100" : "grid-rows-[0fr] opacity-0"
              }`}
            >
              <div className="overflow-hidden">
                <img
                  {...PANEL_IMG}
                  className="mx-auto h-auto w-full max-w-[380px]"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
