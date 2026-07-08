# ExTauri Website

The showcase website for [ExTauri](https://github.com/filipecabaco/ex_tauri), built with
[Francis](https://francis.build) — a boilerplate-free Elixir web framework on top of
Plug and Bandit.

## Structure

- `lib/ex_tauri_website/router.ex` — Francis router: `/` (showcase page), `/health`, static assets under `/assets`, plus secure headers and CSP
- `lib/ex_tauri_website/views/home/index.html.eex` — the page template
- `priv/static/` — CSS, JS, and images, served by `Plug.Static` with optional digest support via `mix francis.digest`

## Development

```bash
mix deps.get
mix francis.server          # http://localhost:4000
iex -S mix francis.server   # with an IEx console
```

Set `PORT` to serve on a different port.

## Tests

```bash
mix test
```

## Production

Digest static assets and build a release:

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
_build/prod/rel/ex_tauri_website/bin/ex_tauri_website start
```

Or build the container image:

```bash
docker build -t ex_tauri_website .
docker run -p 4000:4000 ex_tauri_website
```
