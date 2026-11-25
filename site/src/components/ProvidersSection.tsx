import { useEffect, useRef, useState } from "react";
import * as c from "@/content";
import { LOGO } from "@/lib/marks";

const LOGOS: Record<string, string> = {
  Claude: "/cover/claude.svg",
  Codex: "/cover/codex.svg",
  Cursor: "/cover/cursor.svg",
};

const onLight = (name: string) => (name === "Claude" ? "" : "invert");

/* Normalized horizontal anchor positions (matching 140, 340, 540 in a 680px canvas) */
const PROVIDER_FRACTIONS = [140 / 680, 340 / 680, 540 / 680] as const;
const DIAGRAM_HEIGHT = 314;

const WIRE_STYLE = {
  strokeDasharray: "4 4",
  strokeLinecap: "round" as const,
};

export function ProvidersSection() {
  const [activeNode, setActiveNode] = useState<string | null>(null);
  const diagramRef = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(680);

  /* Keep SVG viewBox in 1:1 CSS pixels so curves, dashes and animated circles never distort on mobile */
  useEffect(() => {
    const el = diagramRef.current;
    if (!el || typeof ResizeObserver === "undefined") return;
    const update = () => {
      const next = Math.round(el.clientWidth);
      if (next > 0) setWidth(next);
    };
    update();
    const observer = new ResizeObserver(update);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const cx = width / 2;
  const xs = PROVIDER_FRACTIONS.map((f) => f * width);
  const r = 12;

  const stemPath = `M ${cx} 88 V 143`;
  const leftBusPath = `M ${cx} 186 Q ${cx} 198 ${cx - r} 198 H ${xs[0] + r} Q ${xs[0]} 198 ${xs[0]} 210 V 230`;
  const rightBusPath = `M ${cx} 186 Q ${cx} 198 ${cx + r} 198 H ${xs[2] - r} Q ${xs[2]} 198 ${xs[2]} 210 V 230`;
  const innerBranchesPath = `M ${xs[1]} 186 V 230`;

  const branchMotionPaths = [
    `M ${cx} 143 V 186 Q ${cx} 198 ${cx - r} 198 H ${xs[0] + r} Q ${xs[0]} 198 ${xs[0]} 210 V 230`,
    `M ${cx} 143 V 230`,
    `M ${cx} 143 V 186 Q ${cx} 198 ${cx + r} 198 H ${xs[2] - r} Q ${xs[2]} 198 ${xs[2]} 210 V 230`,
  ];

  return (
    <section id="providers" className="scroll-mt-[72px] py-20 lg:py-24">
      <div className="mx-auto max-w-[60ch] text-center">
        <h2 className="text-3xl font-semibold tracking-tight text-balance sm:text-4xl">
          Your tools already know you
        </h2>
        <p className="mt-4 leading-relaxed text-slate-600 text-pretty">
          Uzzy reuses the existing sessions on your Mac to check usage limits directly with each
          provider. No extra sign-in, no API keys, no Uzzy server, and readings stay in memory only.
        </p>
      </div>

      {/* Connected SVG node diagram: Uzzy U tile -> stacked Mac sessions / Read-only bridge -> 4 square provider logos */}
      <div
        ref={diagramRef}
        className="relative mx-auto mt-12 h-[314px] w-full max-w-[680px]"
        style={{
          backgroundImage: "radial-gradient(var(--color-slate-300) 1px, transparent 1px)",
          backgroundSize: "18px 18px",
        }}
      >
        {/* Soft radial fade so the dot grid blends seamlessly into slate-50 */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0"
          style={{
            background:
              "radial-gradient(ellipse 72% 72% at 50% 50%, transparent 40%, var(--color-slate-50) 100%)",
          }}
        />

        {/* 1:1 pixel SVG paths + animated data pulses (Uzzy -> Mac sessions -> 4 providers -> Mac sessions -> Uzzy) */}
        <svg
          aria-hidden="true"
          viewBox={`0 0 ${width} ${DIAGRAM_HEIGHT}`}
          fill="none"
          className="pointer-events-none absolute inset-0 size-full"
        >
          <path
            d={`M ${cx} 88 V 186`}
            stroke="var(--color-slate-300)"
            strokeWidth="1.5"
            {...WIRE_STYLE}
          />
          <path d={leftBusPath} stroke="var(--color-slate-300)" strokeWidth="1.5" {...WIRE_STYLE} />
          <path
            d={rightBusPath}
            stroke="var(--color-slate-300)"
            strokeWidth="1.5"
            {...WIRE_STYLE}
          />
          <path
            d={innerBranchesPath}
            stroke="var(--color-slate-300)"
            strokeWidth="1.5"
            {...WIRE_STYLE}
          />

          {/* Animated pulse dots: Uzzy -> Mac sessions -> 4 providers -> Mac sessions -> Uzzy */}
          <g key={width} className="motion-reduce:hidden">
            <circle
              r="3.2"
              fill="var(--color-slate-900)"
              stroke="#ffffff"
              strokeWidth="1.2"
              opacity="0"
            >
              <animateMotion
                dur="5.6s"
                repeatCount="indefinite"
                path={stemPath}
                calcMode="spline"
                keyTimes="0;0.14;0.76;0.90;1"
                keyPoints="0;1;1;0;0"
                keySplines="0.4 0 0.2 1; 0 0 1 1; 0.4 0 0.2 1; 0 0 1 1"
              />
              <animate
                attributeName="opacity"
                dur="5.6s"
                repeatCount="indefinite"
                values="0;1;1;0;0;1;1;0;0"
                keyTimes="0;0.02;0.12;0.14;0.76;0.78;0.88;0.90;1"
              />
            </circle>

            {branchMotionPaths.map((d, idx) => (
              <circle
                key={idx}
                r="3.2"
                fill="var(--color-slate-900)"
                stroke="#ffffff"
                strokeWidth="1.2"
                opacity="0"
              >
                <animateMotion
                  dur="5.6s"
                  repeatCount="indefinite"
                  path={d}
                  calcMode="spline"
                  keyTimes="0;0.14;0.42;0.48;0.76;1"
                  keyPoints="0;0;1;1;0;0"
                  keySplines="0 0 1 1; 0.4 0 0.2 1; 0 0 1 1; 0.4 0 0.2 1; 0 0 1 1"
                />
                <animate
                  attributeName="opacity"
                  dur="5.6s"
                  repeatCount="indefinite"
                  values="0;0;1;1;0;0;1;1;0;0"
                  keyTimes="0;0.14;0.17;0.40;0.42;0.48;0.51;0.74;0.76;1"
                />
              </circle>
            ))}
          </g>
        </svg>

        {/* Port anchor dots */}
        <span
          aria-hidden="true"
          className="pointer-events-none absolute top-[88px] left-1/2 z-10 size-2 -translate-x-1/2 -translate-y-1/2 rounded-full border-[1.5px] border-slate-400 bg-white"
        />
        {PROVIDER_FRACTIONS.map((f) => (
          <span
            key={f}
            aria-hidden="true"
            style={{ left: `${f * 100}%` }}
            className="pointer-events-none absolute top-[230px] z-10 size-2 -translate-x-1/2 -translate-y-1/2 rounded-full border-[1.5px] border-slate-400 bg-white"
          />
        ))}

        {/* Top node: Uzzy U mark only, with host-only tooltip for optional daily GitHub update check */}
        <div
          className="group absolute top-[24px] left-1/2 z-20 -translate-x-1/2"
          onMouseEnter={() => setActiveNode("Uzzy")}
          onMouseLeave={() => setActiveNode((prev) => (prev === "Uzzy" ? null : prev))}
        >
          <button
            type="button"
            aria-label="Uzzy: optional daily update check via api.github.com"
            aria-describedby="provider-tooltip-uzzy"
            onClick={() => setActiveNode((prev) => (prev === "Uzzy" ? null : "Uzzy"))}
            onKeyDown={(e) => {
              if (e.key === "Escape") setActiveNode(null);
            }}
            onFocus={() => setActiveNode("Uzzy")}
            onBlur={() => setActiveNode((prev) => (prev === "Uzzy" ? null : prev))}
            className="grid size-16 cursor-pointer place-items-center rounded-2xl bg-slate-950 text-slate-50 shadow-[0_0_0_6px_rgb(15_23_42/0.06),0_14px_28px_-10px_rgb(15_23_42/0.45)] transition-transform duration-150 hover:scale-[1.03] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-slate-900"
          >
            <svg className="size-7" viewBox="0 0 32 32" fill="currentColor" aria-hidden="true">
              <path d={LOGO} />
            </svg>
          </button>

          <div
            id="provider-tooltip-uzzy"
            role="tooltip"
            className={`pointer-events-none absolute bottom-[calc(100%+10px)] left-1/2 z-30 flex -translate-x-1/2 items-center rounded-lg bg-slate-900 px-3 py-1.5 text-xs whitespace-nowrap text-slate-50 shadow-lg transition-[opacity,translate] duration-150 ${
              activeNode === "Uzzy" ? "translate-y-0 opacity-100" : "translate-y-1 opacity-0"
            }`}
          >
            <code className="font-mono text-[11px] text-slate-200">api.github.com</code>
            <span
              aria-hidden="true"
              className="absolute -bottom-1 left-1/2 size-2 -translate-x-1/2 rotate-45 bg-slate-900"
            />
          </div>
        </div>

        {/* Central bridge pill: stacked column (Mac sessions / Read-only) with animate-ping green dot */}
        <div className="absolute top-[143px] left-1/2 z-20 flex h-[46px] -translate-x-1/2 -translate-y-1/2 flex-col items-center justify-center rounded-2xl border border-slate-300/90 bg-white px-4 text-center shadow-[0_8px_20px_-8px_rgb(15_23_42/0.14)]">
          <span className="inline-flex items-center gap-1.5 text-xs leading-tight font-semibold whitespace-nowrap text-slate-900">
            <span className="relative flex size-1.5" aria-hidden="true">
              <span className="absolute inline-flex size-full animate-ping rounded-full bg-emerald-400 opacity-75 motion-reduce:hidden" />
              <span className="relative inline-flex size-1.5 rounded-full bg-emerald-500" />
            </span>
            Mac sessions
          </span>
          <span className="text-[11px] leading-tight font-medium whitespace-nowrap text-slate-500">
            Read-only
          </span>
        </div>

        {/* Bottom row: 4 square logo-only provider tiles with host-only tooltips */}
        <ul aria-label="Supported providers" className="contents">
          {c.providers.map((p, idx) => {
            const isOpen = activeNode === p.name;
            const tooltipAlign =
              idx === 0
                ? "left-0 lg:left-1/2 lg:-translate-x-1/2"
                : idx === c.providers.length - 1
                  ? "right-0 lg:left-1/2 lg:right-auto lg:-translate-x-1/2"
                  : "left-1/2 -translate-x-1/2";
            const arrowAlign =
              idx === 0
                ? "left-7 lg:left-1/2 lg:-translate-x-1/2"
                : idx === c.providers.length - 1
                  ? "right-7 lg:left-1/2 lg:right-auto lg:-translate-x-1/2"
                  : "left-1/2 -translate-x-1/2";

            return (
              <li
                key={p.name}
                style={{ left: `${PROVIDER_FRACTIONS[idx] * 100}%` }}
                className="absolute top-[230px] z-20 -translate-x-1/2"
                onMouseEnter={() => setActiveNode(p.name)}
                onMouseLeave={() => setActiveNode((prev) => (prev === p.name ? null : prev))}
              >
                <button
                  type="button"
                  aria-label={`${p.name}: connects to ${p.hosts.join(" and ")}`}
                  aria-describedby={`provider-tooltip-${p.name.toLowerCase()}`}
                  onClick={() => setActiveNode((prev) => (prev === p.name ? null : p.name))}
                  onKeyDown={(e) => {
                    if (e.key === "Escape") setActiveNode(null);
                  }}
                  onFocus={() => setActiveNode(p.name)}
                  onBlur={() => setActiveNode((prev) => (prev === p.name ? null : prev))}
                  className={`grid size-[56px] cursor-pointer place-items-center rounded-2xl border bg-white transition-all duration-150 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-slate-900 sm:size-[60px] ${
                    isOpen
                      ? "border-slate-400 shadow-[0_0_0_4px_rgb(15_23_42/0.05),0_10px_24px_-10px_rgb(15_23_42/0.24)]"
                      : "border-slate-200 shadow-[0_8px_20px_-10px_rgb(15_23_42/0.16),0_1px_2px_rgb(15_23_42/0.04)] hover:border-slate-300"
                  }`}
                >
                  <img
                    src={LOGOS[p.name]}
                    alt=""
                    aria-hidden="true"
                    width={26}
                    height={p.name === "Cursor" ? 28 : 26}
                    loading="lazy"
                    decoding="async"
                    className={onLight(p.name)}
                  />
                </button>

                <div
                  id={`provider-tooltip-${p.name.toLowerCase()}`}
                  role="tooltip"
                  className={`pointer-events-none absolute top-[calc(100%+10px)] z-30 flex max-w-[calc(100vw-3rem)] items-center rounded-lg bg-slate-900 px-3 py-1.5 text-xs text-slate-50 shadow-lg transition-[opacity,translate] duration-150 sm:whitespace-nowrap ${tooltipAlign} ${
                    isOpen ? "translate-y-0 opacity-100" : "-translate-y-1 opacity-0"
                  }`}
                >
                  <span
                    aria-hidden="true"
                    className={`absolute -top-1 size-2 rotate-45 bg-slate-900 ${arrowAlign}`}
                  />
                  <code className="font-mono text-[11px] text-slate-200">
                    {p.hosts.join(" · ")}
                  </code>
                </div>
              </li>
            );
          })}
        </ul>
      </div>

      <p className="mt-4 text-center text-xs text-slate-500 text-pretty">
        Hover any logo to see the exact host Uzzy connects to.
      </p>
    </section>
  );
}
