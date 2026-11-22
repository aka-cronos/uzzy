import * as c from "@/content";
import { MENU_BAR } from "@/lib/marks";

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
  return (
    <section id="features" className="scroll-mt-[72px] py-20 lg:py-24">
      <h2 className="text-3xl font-semibold tracking-tight text-balance sm:text-4xl">
        Built to stay clear and out of your way
      </h2>

      <div className="mt-10 grid gap-8 lg:grid-cols-3 lg:gap-9">
        {c.features.map((f, cardIdx) => (
          <article key={f.title} className="flex flex-col gap-5">
            <div className="feature-stage @container relative flex aspect-[4/3] flex-col overflow-hidden rounded-2xl bg-slate-950 text-[13px] font-semibold text-slate-50 select-none">
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
                      decoding="async"
                      style={{
                        width: `min(${f.popoverWidth}px, ${f.popoverWidth === 432 ? "106cqw" : "104cqw"})`,
                      }}
                      className={`feature-popover ${cardIdx === 1 ? "feature-popover-2" : ""} pointer-events-none absolute ${f.popoverTop} left-1/2 h-auto max-w-none -translate-x-1/2 origin-top`}
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
                  <div className="feature-notifs relative z-10 flex flex-col items-end gap-2.5 px-4 pt-1.5">
                    {f.images.map((src, idx) => (
                      <div key={src} className="relative aspect-[690/116] w-full max-w-[345px]">
                        <img
                          src={src}
                          width={423}
                          height={165}
                          alt={idx === 0 ? f.imageAlt : ""}
                          loading="lazy"
                          decoding="async"
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
