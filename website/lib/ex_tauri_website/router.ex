defmodule ExTauriWebsite.Router do
  use Francis,
    static: [from: {:ex_tauri_website, "priv/static"}, at: "/assets", gzip: true],
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

  get("/", &ExTauriWebsite.Controllers.Home.index/1)

  unmatched(fn conn ->
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(404, Francis.ErrorPage.render(404))
  end)
end
