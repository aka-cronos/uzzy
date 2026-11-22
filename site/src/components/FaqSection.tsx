import { PlusIcon, XLogoIcon } from "@phosphor-icons/react";
import * as c from "@/content";
import { buttonVariants } from "@/components/ui/button";

const focus = "focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-slate-900";
const summaryClass = `flex min-h-14 cursor-pointer list-none items-center justify-between gap-4 rounded text-lg font-semibold text-balance [&::-webkit-details-marker]:hidden ${focus}`;
const plusIcon =
  "shrink-0 text-slate-500 transition-transform duration-200 ease-out-strong group-open:rotate-45";

export function FaqSection() {
  return (
    <section id="faq" className="scroll-mt-[72px] py-20 lg:py-24">
      <div className="grid items-start gap-12 lg:grid-cols-[minmax(0,400px)_1fr] lg:gap-16">
        {/* Left column: title, maker note and direct feedback links */}
        <div>
          <h2 className="text-3xl font-semibold tracking-tight text-balance sm:text-4xl">
            The practical details
          </h2>
          <p className="mt-4 leading-relaxed text-slate-600 text-pretty">
            I’m{" "}
            <a
              href={c.X_URL}
              className={`underline underline-offset-2 hover:text-slate-900 ${focus}`}
            >
              @{c.MAKER}
            </a>
            , a designer who got tired of checking four places, so I built Uzzy. Found a bug, have
            an idea or want another provider? Send me a message on X.
          </p>
          <div className="mt-7 flex flex-wrap items-center gap-x-5 gap-y-3">
            <a href={c.X_URL} className={buttonVariants()}>
              <XLogoIcon size={18} aria-hidden="true" />
              Message me on X
            </a>
            <a
              href={`${c.REPO_URL}/issues`}
              className={`inline-flex min-h-11 items-center rounded text-sm font-medium text-slate-600 underline-offset-4 transition-colors duration-200 hover:text-slate-900 hover:underline ${focus}`}
            >
              Open an issue
            </a>
          </div>
        </div>

        {/* Right column: accordion list */}
        <div className="divide-y divide-slate-200 border-y border-slate-200">
          {c.faqs.map((faq, idx) => (
            <details key={faq.question} className="group py-2" open={idx === 0}>
              <summary className={summaryClass}>
                {faq.question}
                <PlusIcon size={20} aria-hidden="true" className={plusIcon} />
              </summary>
              <p className="pr-7 pb-5 leading-relaxed text-slate-600 text-pretty">{faq.answer}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}
