# ExTauri Website

The showcase website for [ExTauri](https://github.com/filipecabaco/ex_tauri), built with
[Francis](https://francis.build) and [Tailwind CSS](https://tailwindcss.com), following the
structure of [francis_site](https://github.com/francis-build/francis_site).

## Structure

- `lib/ex_tauri_website.ex` — the whole app: a single `use Francis` module with `/`, `/health`, static file serving, secure headers, and CSP
- `priv/templates/index.html.eex` — the page template, styled with Tailwind utilities
- `assets/css/app.css` — Tailwind v4 entrypoint (theme tokens + component classes)
- `priv/static/` — JS, images, and the compiled `tw.css` (build output, not committed)

## Development

```bash
mix deps.get
mix assets.build            # compile Tailwind + digest static assets
mix francis.server          # http://localhost:4000
iex -S mix francis.server   # with an IEx console
```

Set `PORT` to serve on a different port. While iterating on styles, rebuild CSS
with `mix tailwind default` (or run `mix tailwind default -- --watch` in a
second terminal).

## Tests

```bash
mix test
```

## Production

```bash
docker build -t ex_tauri_website .
docker run -p 4000:4000 ex_tauri_website
```

Or build a release directly with `MIX_ENV=prod mix do assets.build, release`.
