import { DownloadSimpleIcon } from "@phosphor-icons/react";
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
        <DownloadSimpleIcon
          size={18}
          weight="bold"
          aria-hidden="true"
          className="transition-transform duration-200 ease-out-strong group-hover/button:translate-y-0.5"
        />
      )}
      {label}
    </a>
  );
}
