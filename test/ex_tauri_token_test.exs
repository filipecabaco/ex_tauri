defmodule ExTauri.TokenTest do
  # The token lives in a persistent_term and comes from the environment.
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias ExTauri.Install.Helpers

  @token String.duplicate("a1b2c3d4", 8)

  setup do
    System.put_env("EX_TAURI_TOKEN", @token)
    :persistent_term.erase({ExTauri.Token, :token})

    on_exit(fn ->
      System.delete_env("EX_TAURI_TOKEN")
      :persistent_term.erase({ExTauri.Token, :token})
    end)
  end

  defp guard(conn, opts \\ []), do: ExTauri.Token.Plug.call(conn, ExTauri.Token.Plug.init(opts))

  describe "the token" do
    test "is the shell's when it hands one over, and compared whole" do
      assert ExTauri.Token.get() == @token
      assert ExTauri.Token.from_shell?()
      assert ExTauri.Token.valid?(@token)
      refute ExTauri.Token.valid?(String.slice(@token, 0..-2//1))
      refute ExTauri.Token.valid?(nil)
    end

    test "is made here, and kept, without the shell" do
      System.delete_env("EX_TAURI_TOKEN")
      token = ExTauri.Token.get()

      assert byte_size(token) >= 32
      assert ExTauri.Token.get() == token
      refute ExTauri.Token.from_shell?()
    end
  end

  describe "the plug" do
    test "trades the token in the URL for a cookie, and redirects without it" do
      conn = guard(conn(:get, "/?ex_tauri_token=#{@token}&tab=mesh"))

      assert conn.halted
      assert conn.status == 303
      assert get_resp_header(conn, "location") == ["/?tab=mesh"]

      assert %{value: @token, http_only: true, same_site: "Strict"} =
               conn.resp_cookies["ex_tauri_80"]
    end

    test "lets in the window's cookie, or a bearer token, and nothing else" do
      ok = conn(:post, "/api/rpc") |> put_req_cookie("ex_tauri_80", @token) |> guard()
      refute ok.halted

      bearer = conn(:post, "/api/rpc") |> put_req_header("authorization", "Bearer #{@token}")
      refute guard(bearer).halted

      assert %{status: 401, halted: true} = guard(conn(:post, "/api/rpc"))

      assert %{status: 401} =
               conn(:post, "/api/rpc") |> put_req_cookie("ex_tauri_80", "guess") |> guard()

      # A cookie for another port is another app's.
      assert %{status: 401} =
               conn(:post, "/api/rpc") |> put_req_cookie("ex_tauri_4000", @token) |> guard()
    end

    test "refuses a wrong token in the URL, and one sent other than by GET" do
      assert %{status: 401, resp_cookies: cookies} = guard(conn(:get, "/?ex_tauri_token=guess"))
      assert cookies == %{}
      assert %{status: 401} = guard(conn(:post, "/?ex_tauri_token=#{@token}"))
    end

    test "guards only the paths it is given" do
      assert %{status: 401} = guard(conn(:get, "/api/events"), only: ["/api"])
      assert %{status: 401} = guard(conn(:get, "/api"), only: ["/api"])
      refute guard(conn(:get, "/"), only: ["/api"]).halted
      refute guard(conn(:get, "/apiary"), only: ["/api"]).halted
      assert %{status: 401} = guard(conn(:get, "/"))
    end
  end

  describe "the shells" do
    test "the desktop shell hands the backend a token and opens the window with it" do
      src = Helpers.main_src("localhost", "4000", "test_app")

      assert src =~ ~s|("EX_TAURI_TOKEN".to_string(), TOKEN.get_or_init(launch_token).clone())|
      assert src =~ ~s|/?ex_tauri_token={}", port, token)|
    end

    test "the iOS shell does too, and adds the dev server's to its URL" do
      src = Helpers.mobile_src("localhost")

      assert src =~ ~s|("EX_TAURI_TOKEN", super::TOKEN.get_or_init(super::random_secret).clone())|
      assert src =~ ~s|:{port}/?ex_tauri_token={token}"|
      assert src =~ ~s|std::env::var("EX_TAURI_TOKEN")|
    end
  end
end
