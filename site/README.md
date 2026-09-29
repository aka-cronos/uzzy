# uzzy.app

The landing page for Uzzy, served at <https://uzzy.app>. It is an [Astro](https://astro.build) site with static output, styled with Tailwind CSS and [shadcn/ui](https://ui.shadcn.com) components on [Base UI](https://base-ui.com) through `@astrojs/react`. The React components render to HTML at build time, so the page's own code ships no client JavaScript. On `uzzy.app`, Cloudflare injects its Web Analytics beacon into the served HTML; the repo contains no analytics script (see step 5 of the Cloudflare setup below).

## Develop

From `site/`, with Node 22.12 or later and pnpm:

```sh
pnpm install --frozen-lockfile
pnpm dev       # http://localhost:4321
pnpm typecheck # check Astro and TypeScript files
pnpm build     # typecheck, then static site in dist/
```

The copy lives in `src/content.ts` and the page in `src/pages/index.astro`. Every image the site uses lives in `public/`, including copies of the brand marks, so this directory builds on its own.

### Icons

`public/favicon.ico` (32×32), `public/icon-192.png` and `public/icon-512.png` (listed in `public/site.webmanifest`) come from `public/brand/app-icon-1024.png`. That PNG is a macOS app icon, with the opaque rounded square at 824×824 in the middle of a transparent margin that only holds its drop shadow; the commands crop that margin away so the icon fills the favicon and home-screen sizes. From `site/public/`, with only macOS's `sips`:

```sh
tmp=$(mktemp -d)
sips --cropToHeightWidth 824 824 brand/app-icon-1024.png --out "$tmp/icon.png"
sips -z 512 512 "$tmp/icon.png" --out icon-512.png
sips -z 192 192 "$tmp/icon.png" --out icon-192.png
sips -z 32 32 "$tmp/icon.png" --out "$tmp/icon-32.png"
sips -s format ico "$tmp/icon-32.png" --out favicon.ico
rm -r "$tmp"
```

Run them again whenever the app icon changes.

## Hosting

Cloudflare serves the site from a static-only Worker named `uzzy-site`, configured in `wrangler.jsonc`: no script, just `dist/` as static assets, with Astro's `404.html` for unknown paths and automatic trailing-slash handling. `pnpm exec wrangler dev` serves the built `dist/` the way production does.

Workers Builds builds and deploys it from this repo: every push to `main` that touches `site/` deploys to production, and every pull request that touches `site/` gets a preview URL and a check.

### One-time Cloudflare setup

Done once by hand in the Cloudflare dashboard; nothing in the repo does it.

1. **Workers & Pages → Create → Import a repository**, and connect Workers Builds to `aka-cronos/uzzy`. Name the Worker `uzzy-site`, matching `wrangler.jsonc`.
2. Under the Worker's **Settings → Build**:
   - **Root directory**: `site/`.
   - **Build command**: `pnpm build`. **Deploy command**: `npx wrangler deploy` (the default).
   - **Build watch paths**: include `site/*`, so changes elsewhere in the repo don't trigger a build.
   - **Branch control**: production branch `main`, with **builds for non-production branches** enabled so pull requests get preview URLs.
3. **Settings → Domains & Routes → Add → Custom domain**: `uzzy.app`. The `uzzy.app` zone must be on the same Cloudflare account.
4. Redirect `www.uzzy.app` to the apex: add a proxied DNS record for `www` (for example `AAAA` to `100::`), then a **Rules → Redirect Rules** rule from `www.uzzy.app/*` to `https://uzzy.app/${1}` with status 301, keeping the query string.
5. **Web Analytics → Add a site**: `uzzy.app`, with automatic setup, so Cloudflare injects the beacon on the proxied hostname. Don't copy the JS snippet into the site. `*.workers.dev` and preview URLs aren't proxied, so they aren't counted. Keep **Bot Fight Mode** and challenges off on the `uzzy.app` zone: they set cookies (`__cf_bm`, `cf_clearance`), and the Privacy copy in `src/content.ts` promises none. Switching them on means updating that copy.

**Launch order**: the download buttons point at `releases/latest/download/Uzzy.dmg`, which 404s until the first release exists. Merging the site and deploying to `*.workers.dev` is fine, but don't attach the `uzzy.app` custom domain or switch on Web Analytics (steps 3 to 5) until the `0.1.0` release is published.
