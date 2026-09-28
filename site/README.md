# uzzy.app

The landing page for Uzzy, served at <https://uzzy.app>. It is an [Astro](https://astro.build) site with static output, styled with Tailwind CSS and [shadcn/ui](https://ui.shadcn.com) components on [Base UI](https://base-ui.com) through `@astrojs/react`. The React components render to HTML at build time, so the page ships no client JavaScript.

## Develop

From `site/`, with Node 22.12 or later and pnpm:

```sh
pnpm install --frozen-lockfile
pnpm dev      # http://localhost:4321
pnpm build    # static site in dist/
```

The copy lives in `src/content.ts` and the page in `src/pages/index.astro`. Every image the site uses lives in `public/`, including copies of the brand marks, so this directory builds on its own.

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

**Launch order**: the download buttons point at `releases/latest/download/Uzzy.dmg`, which 404s until the first release exists. Merging the site and deploying to `*.workers.dev` is fine, but don't attach the `uzzy.app` custom domain (steps 3 and 4) until the `0.1.0` release is published.
