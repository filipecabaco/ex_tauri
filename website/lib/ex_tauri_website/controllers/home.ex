defmodule ExTauriWebsite.Controllers.Home do
  def index(conn) do
    html(conn, ExTauriWebsite.Views.Home.index(%{year: Date.utc_today().year}))
  end

  defp html(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, body)
  end
end
