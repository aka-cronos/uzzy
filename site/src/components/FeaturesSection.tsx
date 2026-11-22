import { useEffect, useRef, useState } from "react";
import * as c from "@/content";
import { MENU_BAR } from "@/lib/marks";

const MOTION =
  "transition-[opacity,translate,scale] duration-500 ease-out-strong motion-reduce:transition-opacity motion-reduce:translate-x-0 motion-reduce:translate-y-0 motion-reduce:scale-100";

/* Hero-scale wallpaper anchors so each card looks like a true 1:1 desktop close-up instead of a shrunken background */
const CLOSEUP_OFFSETS = [
  "top-0 right-[-40px]",
  "top-[-20px] right-0",
  "top-[-10px] right-[-120px]",
] as const;

function UzzyGlyph({ className }: { className: string }) {
  return (
    <svg className={className} viewBox="0 0 32 32" fill="currentColor" aria-hidden="true">
      <path d={MENU_BAR} />
    </svg>
  );
}

function StatusCluster({ date, time }: { date: string; time: string }) {
  return (
    <>
      <img
        src="/cover/control-center.svg"
        alt=""
        width="31.15"
        height="21.41"
        loading="lazy"
        decoding="async"
        aria-hidden="true"
        className="shrink-0"
      />
      <time aria-hidden="true" className="pl-[9px] whitespace-nowrap tabular-nums">
        <span className="hidden xl:inline">{date} </span>
        {time}
      </time>
    </>
  );
}

export function FeaturesSection() {
  const sectionRef = useRef<HTMLElement>(null);
  /* Default true so SSR HTML and no-JS always show the screenshots; JS arms scroll entrance when below the fold. */
  const [visible, setVisible] = useState(true);

  useEffect(() => {
    const el = sectionRef.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    if (el.getBoundingClientRect().top <= window.innerHeight * 0.95) return;

    setVisible(false);
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setVisible(true);
          observer.disconnect();
        }
      },
      { threshold: 0.2 },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return (
    <section ref={sectionRef} id="features" className="scroll-mt-[72px] py-20 lg:py-24">
      <h2 className="text-3xl font-semibold tracking-tight text-balance sm:text-4xl">
        Built to stay clear and out of your way
      </h2>

      <div className="mt-10 grid gap-8 lg:grid-cols-3 lg:gap-9">
        {c.features.map((f, cardIdx) => (
          <article key={f.title} className="flex flex-col gap-5">
            <div className="@container relative flex aspect-[4/3] flex-col overflow-hidden rounded-2xl bg-slate-950 text-[13px] font-semibold text-slate-50 select-none">
              <img
                src="/cover/bg.jpg"
                alt=""
                loading="lazy"
                decoding="async"
                className={`pointer-events-none absolute h-[900px] w-[1520px] max-w-none object-cover ${
                  CLOSEUP_OFFSETS[cardIdx] ?? CLOSEUP_OFFSETS[0]
                }`}
              />

              {f.kind === "popover" ? (
                <div className="relative z-10 grid grid-cols-[1fr_auto_1fr] items-center py-2">
                  <span className="relative col-start-2 flex items-center rounded-full bg-[#323234] px-[9px] py-1">
                    <UzzyGlyph className="-my-0.5 size-[18px]" />
                    <img
                      src={f.images[0]}
                      width={f.popoverWidth}
                      alt={f.imageAlt}
                      loading="lazy"
                      style={{
                        width: `min(${f.popoverWidth}px, ${f.popoverWidth === 432 ? "106cqw" : "104cqw"})`,
                        transitionDelay: `${cardIdx * 90}ms`,
                      }}
                      className={`pointer-events-none absolute ${f.popoverTop} left-1/2 h-auto max-w-none -translate-x-1/2 origin-top ${MOTION} ${
                        visible
                          ? "translate-y-0 scale-100 opacity-100"
                          : "-translate-y-2 scale-[0.96] opacity-0"
                      }`}
                    />
                  </span>
                  <div className="flex items-center pl-1 whitespace-nowrap">
                    <StatusCluster date="Thu 24 Sep" time="9:00 AM" />
                  </div>
                </div>
              ) : (
                <>
                  <div className="relative z-10 flex items-center justify-end px-4 py-2">
                    <UzzyGlyph className="mr-1.5 size-[18px]" />
                    <StatusCluster date="Sat 21 Nov" time="9:00 PM" />
                  </div>
                  <div
                    style={{ transitionDelay: "120ms" }}
                    className={`relative z-10 flex flex-col items-end gap-2.5 px-4 pt-1.5 ${MOTION} ${
                      visible ? "translate-x-0 opacity-100" : "translate-x-14 opacity-0"
                    }`}
                  >
                    {f.images.map((src, idx) => (
                      <div
                        key={src}
                        className="relative aspect-[690/116] w-full max-w-[345px]"
                      >
                        <img
                          src={src}
                          width={423}
                          height={165}
                          alt={idx === 0 ? f.imageAlt : ""}
                          loading="lazy"
                          className="pointer-events-none absolute top-[-75.86%] left-[-18.12%] h-auto w-[122.61%] max-w-none"
                        />
                      </div>
                    ))}
                  </div>
                </>
              )}
            </div>

            <div>
              <h3 className="text-lg font-semibold text-balance text-slate-900">{f.title}</h3>
              <p className="mt-1.5 leading-relaxed text-slate-600 text-pretty">{f.body}</p>
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
