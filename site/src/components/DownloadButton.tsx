import type { VariantProps } from "class-variance-authority";

import { Button, type buttonVariants } from "@/components/ui/button";
import { DOWNLOAD_URL } from "@/content";

// Rendered at build time: a plain link to the latest release's DMG, no client JS.
export function DownloadButton({
  label = "Download for Mac",
  icon = true,
  variant,
  size,
  className,
}: VariantProps<typeof buttonVariants> & {
  label?: string;
  icon?: boolean;
  className?: string;
}) {
  return (
    <Button asChild variant={variant} size={size} className={className}>
      <a href={DOWNLOAD_URL}>
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
    </Button>
  );
}
