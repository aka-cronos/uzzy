import { useEffect, useRef, useState } from "react";
import * as c from "@/content";
import { MENU_BAR } from "@/lib/marks";

const MOTION =
  "transition-[opacity,transform] duration-500 ease-out-strong motion-reduce:transition-opacity motion-reduce:transform-none";

function UzzyGlyph({ className }: { className: string }) {
  return (
    <svg className={className} viewBox="0 0 32 32" fill="currentColor" aria-hidden="true">
      <path d={MENU_BAR} />
    </svg>
  );
}

function StatusCluster({ time }: { time: string }) {
  return (
    <>
      <img
        src="/cover/control-center.svg"
        alt=""
        width="31.15"
        height="21.41"
        aria-hidden="true"
        className="shrink-0"
      />
      <time aria-hidden="true" className="pl-[9px] whitespace-nowrap tabular-nums">
        {time}
      </time>
    </>
  );
}

export function FeaturesSection() {
  const sectionRef = useRef<HTMLElement>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const el = sectionRef.current;
    if (!el || typeof IntersectionObserver === "undefined") {
      setVisible(true);
      return;
    }
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
        Different tools. One place to check.
      </h2>

      <div className="mt-10 grid gap-8 md:grid-cols-3 lg:gap-9">
        {c.features.map((f, cardIdx) => (
          <article key={f.title} className="flex flex-col gap-5">
            <div className="relative flex aspect-[4/3] flex-col overflow-hidden rounded-2xl bg-slate-950 text-[13px] font-semibold text-slate-50 select-none">
              <img
                src="/cover/bg.jpg"
                alt=""
                loading="lazy"
                className={`absolute inset-0 size-full scale-115 object-cover ${f.cropPosition}`}
              />

              {f.kind === "popover" ? (
                <div className="relative z-10 grid grid-cols-[1fr_auto_1fr] items-center py-2">
                  <span className="relative col-start-2 flex items-center rounded-full bg-[#323234] px-[9px] py-1">
                    <UzzyGlyph className="-my-0.5 size-[18px]" />
                    <img
                      src={f.images[0]}
                      width={361}
                      alt={f.imageAlt}
                      loading="lazy"
                      style={{ transitionDelay: `${cardIdx * 90}ms` }}
                      className={`pointer-events-none absolute top-[calc(100%+3px)] left-1/2 h-auto w-[min(361px,calc(100vw-48px))] max-w-none -translate-x-1/2 origin-top drop-shadow-[0_18px_32px_rgba(0,0,0,0.65)] ${MOTION} ${
                        visible
                          ? "translate-y-0 scale-100 opacity-100"
                          : "-translate-y-2 scale-[0.96] opacity-0"
                      }`}
                    />
                  </span>
                  <div className="flex items-center pl-1 whitespace-nowrap">
                    <StatusCluster time="Thu 24 Sep 9:00 AM" />
                  </div>
                </div>
              ) : (
                <>
                  <div className="relative z-10 flex items-center justify-end px-4 py-2">
                    <UzzyGlyph className="mr-1.5 size-[18px]" />
                    <StatusCluster time="Sat 21 Nov 9:00 PM" />
                  </div>
                  <div className="relative z-10 flex flex-col items-end gap-2.5 px-4 pt-1.5">
                    {f.images.map((src, idx) => (
                      <img
                        key={src}
                        src={src}
                        width={345}
                        height={58}
                        alt={idx === 0 ? f.imageAlt : ""}
                        loading="lazy"
                        style={{ transitionDelay: `${120 + idx * 110}ms` }}
                        className={`h-auto w-full max-w-[345px] drop-shadow-[0_12px_24px_rgba(0,0,0,0.55)] ${MOTION} ${
                          visible ? "translate-x-0 opacity-100" : "translate-x-5 opacity-0"
                        }`}
                      />
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
