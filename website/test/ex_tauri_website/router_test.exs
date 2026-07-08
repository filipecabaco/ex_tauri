defmodule ExTauriWebsite.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  @opts ExTauriWebsite.Router.init([])

  test "GET / renders the showcase page" do
    conn = conn(:get, "/") |> ExTauriWebsite.Router.call(@opts)

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    assert conn.resp_body =~ "Build native desktop apps"
    assert conn.resp_body =~ "mix ex_tauri.install"
    assert conn.resp_body =~ Integer.to_string(Date.utc_today().year)
  end

  test "GET /health returns ok as JSON" do
    conn = conn(:get, "/health") |> ExTauriWebsite.Router.call(@opts)

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"status" => "ok"}
  end

  test "serves static assets under /assets" do
    conn = conn(:get, "/assets/css/site.css") |> ExTauriWebsite.Router.call(@opts)

    assert conn.status == 200
    assert conn.resp_body =~ ":root"
  end

  test "unknown routes render the 404 page" do
    conn = conn(:get, "/nope") |> ExTauriWebsite.Router.call(@opts)

    assert conn.status == 404
  end

  test "responses include security headers" do
    conn = conn(:get, "/") |> ExTauriWebsite.Router.call(@opts)

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "default-src 'self'"
  end
end
