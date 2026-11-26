import { useEffect, useState } from "react";
import * as c from "@/content";
import { MENU_BAR } from "@/lib/marks";
import { DownloadButton } from "@/components/DownloadButton";

const LOGOS: Record<string, string> = {
  Claude: "/cover/claude.svg",
  Codex: "/cover/codex.svg",
  Cursor: "/cover/cursor.svg",
};

const FINDER_MENUS = ["File", "Edit", "View", "Go", "Window", "Help"] as const;

const PANEL_IMG = {
  src: "/cover/panel.png",
  width: 408,
  height: 991,
  alt: "The Uzzy panel: cards for Claude, Codex and Cursor with their plans, each usage limit with its bar, used percentage and reset time.",
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
  const [isOpen, setIsOpen] = useState(true);
  const [clock, setClock] = useState<{ date: string; time: string } | null>(null);

  useEffect(() => {
    const tick = () => setClock(formatMacClock(new Date()));
    tick();
    const clockTimer = window.setInterval(tick, 15_000);
    return () => window.clearInterval(clockTimer);
  }, []);

  const panelMotion =
    "panel-drop origin-top transition-[opacity,translate,scale] duration-300 ease-out-strong motion-reduce:transition-opacity motion-reduce:translate-y-0 motion-reduce:scale-100";

  return (
    <section className="pt-[88px] pb-12 lg:px-5 lg:pb-16">
      <div className="mx-auto flex max-w-[1600px] flex-col lg:relative lg:h-[clamp(660px,calc(100vh-104px),1040px)] lg:overflow-hidden lg:rounded-2xl lg:bg-slate-950 lg:text-slate-50 lg:shadow-[0_30px_60px_-20px_rgb(15_23_42/0.35)] lg:ring-1 lg:ring-slate-900/10">
        {/* Desktop wallpaper fills the entire hero frame */}
        <img
          src="/cover/bg.jpg"
          alt=""
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 hidden size-full object-cover lg:block"
          loading="eager"
          fetchPriority="high"
        />

        {/* Single HeroCopy (one <h1> in the DOM): light centered above the card on < lg, dark inside the frame on lg+ */}
        <div className="order-1 mx-auto w-full max-w-[1440px] px-6 pt-6 pb-10 sm:px-10 lg:relative lg:z-10 lg:order-2 lg:flex lg:max-w-none lg:flex-1 lg:px-7 lg:py-0">
          <div className="mx-auto w-full lg:grid lg:max-w-[1344px] lg:flex-1 lg:grid-cols-[minmax(0,1fr)_440px] lg:items-center lg:gap-12 lg:py-10">
            <div className="mx-auto flex max-w-[56ch] flex-col items-center gap-6 text-center lg:mx-0 lg:items-start lg:gap-7 lg:text-left">
              <div className="rise flex flex-col gap-4">
                <h1 className="text-4xl leading-[1.08] font-semibold tracking-tight text-balance text-slate-900 sm:text-5xl lg:text-[54px] lg:text-slate-50">
                  {c.hero.title}
                </h1>
                <p className="text-lg leading-relaxed text-slate-600 text-pretty lg:text-slate-300">
                  {c.hero.subtitle}
                </p>
              </div>

              <ul
                className="rise flex flex-wrap justify-center gap-2.5 [--i:1] lg:justify-start"
                aria-label="Supported providers"
              >
                {c.providers.map((p) => (
                  <li
                    key={p.name}
                    className="flex items-center gap-2 rounded-full border border-slate-300 bg-slate-100 px-3.5 py-1 text-sm font-medium text-slate-700 lg:border-white/15 lg:bg-white/[0.08] lg:text-slate-100 lg:backdrop-blur-xs"
                  >
                    <img
                      src={LOGOS[p.name]}
                      alt=""
                      aria-hidden="true"
                      width={16}
                      height={p.name === "Cursor" ? 18 : 16}
                      className={p.name !== "Claude" ? "invert lg:invert-0" : undefined}
                    />
                    {p.name}
                  </li>
                ))}
              </ul>

              <div className="rise flex flex-col items-center gap-3 [--i:2] lg:items-start">
                <div className="flex flex-wrap items-center justify-center gap-x-6 gap-y-3 lg:justify-start">
                  <DownloadButton className="lg:bg-slate-50 lg:text-slate-900 lg:hover:bg-slate-200 lg:focus-visible:outline-slate-50" />
                  <a
                    href={c.REPO_URL}
                    className="inline-flex min-h-11 items-center rounded font-medium text-slate-600 underline-offset-4 transition-colors duration-200 hover:text-slate-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-slate-900 lg:text-slate-300 lg:hover:text-white lg:focus-visible:outline-white"
                  >
                    View on GitHub
                  </a>
                </div>
                <p className="text-sm text-slate-600 text-pretty lg:text-slate-400">
                  Free and open source · Version {c.VERSION} · {c.REQUIREMENTS}
                </p>
              </div>
            </div>
          </div>
        </div>

        {/* Mac menu bar + popover: compact dark card below copy on < lg, top bar of the dark frame on lg+ */}
        <div className="order-2 px-3 sm:px-5 lg:order-1 lg:px-0">
          <div className="relative h-[480px] overflow-hidden rounded-2xl bg-slate-950 text-slate-50 shadow-[0_30px_60px_-20px_rgb(15_23_42/0.35)] ring-1 ring-slate-900/10 sm:h-[560px] lg:h-auto lg:overflow-visible lg:rounded-none lg:bg-transparent lg:shadow-none lg:ring-0">
            <img
              src="/cover/bg.jpg"
              alt=""
              aria-hidden="true"
              className="pointer-events-none absolute inset-0 size-full object-cover lg:hidden"
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
          </div>
        </div>
      </div>
    </section>
  );
}
