defmodule ExTauriWebsite do
  @moduledoc """
  The ExTauri showcase website — a Francis app serving a Tailwind-styled page.
  """
  use Francis,
    static: [at: "/", from: {:ex_tauri_website, "priv/static"}],
    bandit_opts: [port: String.to_integer(System.get_env("PORT") || "4000")]

  plug(Francis.Plug.SecureHeaders)

  plug(Francis.Plug.CSP,
    directives: %{
      "default-src" => "'self'",
      "img-src" => "'self' data:",
      "style-src" => "'self' 'unsafe-inline'",
      "script-src" => "'self'"
    }
  )

  get("/health", fn _ -> %{status: "ok"} end)

  get("/", fn conn ->
    html =
      :code.priv_dir(:ex_tauri_website)
      |> Path.join("templates/index.html.eex")
      |> EEx.eval_file(
        tw_css: Francis.Static.static_path("tw.css"),
        site_js: Francis.Static.static_path("site.js"),
        example_gif: Francis.Static.static_path("images/example.gif"),
        year: Date.utc_today().year
      )

    html(conn, html)
  end)

  unmatched(fn conn ->
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(404, Francis.ErrorPage.render(404))
  end)
end
