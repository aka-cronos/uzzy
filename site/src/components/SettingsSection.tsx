import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import * as c from "@/content";
import { Kbd, KbdGroup } from "@/components/ui/kbd";
import { cn } from "@/lib/utils";

const FOCUS = "focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-slate-900";
const ITEM_STAGGER_MS = [0, 40, 80] as const;

export function SettingsSection() {
  const sectionRef = useRef<HTMLElement>(null);
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const [activeIndex, setActiveIndex] = useState(0);
  const [inView, setInView] = useState(false);
  const [paused, setPaused] = useState(false);

  useEffect(() => {
    const el = sectionRef.current;
    if (!el || typeof IntersectionObserver === "undefined") {
      setInView(true);
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => setInView(entries.some((e) => e.isIntersecting)),
      { threshold: 0.25 },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const handleTabKeyDown = (event: KeyboardEvent<HTMLButtonElement>, idx: number) => {
    const count = c.settingsTabs.length;
    let next: number | null = null;
    if (event.key === "ArrowRight") next = (idx + 1) % count;
    else if (event.key === "ArrowLeft") next = (idx - 1 + count) % count;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = count - 1;
    if (next === null) return;
    event.preventDefault();
    setActiveIndex(next);
    tabRefs.current[next]?.focus();
  };

  return (
    <section ref={sectionRef} id="settings" className="scroll-mt-[72px] py-20 lg:py-24">
      <div className="grid items-center gap-10 lg:grid-cols-2 lg:gap-16">
        {/* Left 50% on desktop (second on mobile): fixed-height transparent frame with each Settings window vertically centered at 1x size */}
        <div className="relative order-2 h-[420px] overflow-hidden sm:h-[580px] lg:order-1 lg:h-[700px]">
          {c.settingsTabs.map((tab, idx) => {
            const isActive = idx === activeIndex;
            return (
              <div
                key={tab.id}
                aria-hidden={!isActive}
                className={cn(
                  "absolute inset-0 flex items-center justify-center transition-[opacity,translate,scale,filter] ease-out motion-reduce:translate-y-0 motion-reduce:scale-100 motion-reduce:blur-none",
                  isActive
                    ? "z-10 translate-y-0 scale-100 opacity-100 blur-none duration-[400ms]"
                    : "pointer-events-none z-0 translate-y-1.5 scale-[0.985] opacity-0 blur-[2px] duration-300",
                )}
              >
                <img
                  src={tab.image}
                  alt={tab.alt}
                  width={tab.width}
                  height={tab.height}
                  loading="lazy"
                  decoding="async"
                  className="max-h-full w-auto max-w-[min(100%,592px)] object-contain"
                />
              </div>
            );
          })}
        </div>

        {/* Right 50% on desktop (first on mobile): vertically centered against the Settings window */}
        <div className="order-1 max-w-[46ch] lg:order-2">
          <h2 className="text-3xl font-semibold tracking-tight text-balance sm:text-4xl">
            Set it up your way, or don’t
          </h2>
          <p className="mt-3 leading-relaxed text-slate-600 text-pretty">
            Open Settings with{" "}
            <KbdGroup className="mx-0.5 align-baseline">
              <Kbd>⌘</Kbd>
              <span className="text-xs text-slate-400">+</span>
              <Kbd>,</Kbd>
            </KbdGroup>{" "}
            from the panel.
          </p>

          <div role="tablist" aria-label="Settings tabs" className="mt-8 flex items-center gap-7">
            {c.settingsTabs.map((tab, idx) => {
              const isActive = idx === activeIndex;
              return (
                <button
                  key={tab.id}
                  ref={(el) => {
                    tabRefs.current[idx] = el;
                  }}
                  id={`settings-tab-${tab.id}`}
                  type="button"
                  role="tab"
                  tabIndex={isActive ? 0 : -1}
                  aria-selected={isActive}
                  aria-controls={`settings-panel-${tab.id}`}
                  onClick={() => setActiveIndex(idx)}
                  onKeyDown={(e) => handleTabKeyDown(e, idx)}
                  onFocus={() => setPaused(true)}
                  onBlur={() => setPaused(false)}
                  className={cn(
                    "relative cursor-pointer pb-1 text-sm transition-[color,scale] duration-150 ease-out-strong active:scale-[0.97] motion-reduce:active:scale-100",
                    isActive
                      ? "font-semibold text-slate-900"
                      : "font-medium text-slate-400 hover:text-slate-600",
                    FOCUS,
                  )}
                >
                  {tab.label}
                  {isActive && (
                    <span
                      aria-hidden="true"
                      className="absolute inset-x-0 bottom-0 h-[2px] overflow-hidden rounded-full bg-slate-200"
                    >
                      <span
                        key={`${tab.id}-${inView ? "run" : "idle"}`}
                        onAnimationEnd={() =>
                          setActiveIndex((prev) => (prev + 1) % c.settingsTabs.length)
                        }
                        style={{
                          animationPlayState: inView && !paused ? "running" : "paused",
                        }}
                        className="settings-progress-bar block h-full w-full bg-slate-900"
                      />
                    </span>
                  )}
                </button>
              );
            })}
          </div>

          <div
            className="mt-7 grid"
            onMouseEnter={() => setPaused(true)}
            onMouseLeave={() => setPaused(false)}
          >
            {c.settingsTabs.map((tab, tabIdx) => {
              const isActive = tabIdx === activeIndex;
              return (
                <ul
                  key={tab.id}
                  id={`settings-panel-${tab.id}`}
                  role="tabpanel"
                  aria-labelledby={`settings-tab-${tab.id}`}
                  aria-hidden={!isActive}
                  className={cn(
                    "col-start-1 row-start-1 space-y-6",
                    isActive ? "z-10" : "pointer-events-none z-0",
                  )}
                >
                  {tab.items.map((item, itemIdx) => (
                    <li
                      key={item.title}
                      style={{
                        transitionDelay: isActive ? `${ITEM_STAGGER_MS[itemIdx] ?? 0}ms` : "0ms",
                      }}
                      className={cn(
                        "transition-[opacity,filter] ease-out motion-reduce:blur-none",
                        isActive
                          ? "opacity-100 blur-none duration-[380ms]"
                          : "opacity-0 blur-[2px] duration-[280ms]",
                      )}
                    >
                      <h3 className="text-base font-semibold text-balance text-slate-900">
                        {item.title}
                      </h3>
                      <p className="mt-1.5 leading-relaxed text-slate-600 text-pretty">
                        {item.body}
                      </p>
                    </li>
                  ))}
                </ul>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
}
