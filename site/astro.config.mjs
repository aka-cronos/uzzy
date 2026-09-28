import { defineConfig } from "astro/config";
import react from "@astrojs/react";
import tailwindcss from "@tailwindcss/vite";

// Static output only: Cloudflare serves dist/ as Worker static assets.
export default defineConfig({
  site: "https://uzzy.app",
  output: "static",
  integrations: [react()],
  vite: { plugins: [tailwindcss()] },
});
