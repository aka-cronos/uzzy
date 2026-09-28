import type { VariantProps } from "class-variance-authority";

import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { DOWNLOAD_URL } from "@/content";

// A link that looks like a button. Base UI's Button always sets role="button",
// which would override this anchor, so the styles come from buttonVariants.
// Rendered at build time: a plain link to the latest release's DMG, no client JS.
export function DownloadButton({
  label = "Download for Mac",
  icon = true,
  variant = "default",
  size = "default",
  className,
}: VariantProps<typeof buttonVariants> & {
  label?: string;
  icon?: boolean;
  className?: string;
}) {
  return (
    <a
      href={DOWNLOAD_URL}
      data-slot="button"
      data-variant={variant}
      data-size={size}
      className={cn(buttonVariants({ variant, size, className }))}
    >
      {icon && (
        // Lucide "download"
        <svg
          className="size-[18px]"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden="true"
        >
          <path d="M12 15V3M7 10l5 5 5-5" />
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
        </svg>
      )}
      {label}
    </a>
  );
}
