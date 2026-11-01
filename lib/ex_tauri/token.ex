defmodule ExTauri.Token do
  @moduledoc """
  A secret for this launch, shared by the app's window and its backend only.

  The backend listens on loopback, where the window reaches it, but so can every
  other program on the machine, and every running app on an iPhone: loopback is
  not private to an app. Checking `Host` and `Origin` stops web pages, not a
  program that sets the headers it likes. The token is what such a program does
  not have.

  The shell makes it at launch (random, never written to disk), hands it to the
  backend as `EX_TAURI_TOKEN`, and opens the window at `/?ex_tauri_token=...`.
  `ExTauri.Token.Plug` trades that for an `HttpOnly`, `SameSite=Strict` cookie and
  then wants the cookie (or `Authorization: Bearer <token>`) on every request it
  guards. A backend started without the shell (`mix run`, a script) makes its own
  token, and the plug logs the URL to open.
  """

  @key {__MODULE__, :token}

  @doc "This launch's token: `EX_TAURI_TOKEN`, or one made now and kept for the VM's life."
  @spec get() :: String.t()
  def get do
    case :persistent_term.get(@key, nil) do
      nil ->
        token = from_env() || generate()
        :persistent_term.put(@key, token)
        token

      token ->
        token
    end
  end

  @doc "Whether the token came from the shell (false when this VM made its own)."
  @spec from_shell?() :: boolean()
  def from_shell?, do: from_env() == get()

  @doc "Whether `candidate` is this launch's token, compared in constant time."
  @spec valid?(term()) :: boolean()
  def valid?(candidate) when is_binary(candidate) do
    token = get()
    byte_size(candidate) == byte_size(token) and :crypto.hash_equals(candidate, token)
  end

  def valid?(_candidate), do: false

  defp from_env do
    case System.get_env("EX_TAURI_TOKEN") do
      token when is_binary(token) and byte_size(token) >= 32 -> token
      _ -> nil
    end
  end

  defp generate, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  if Code.ensure_loaded?(Plug) do
    defmodule Plug do
      @moduledoc """
      Lets through only requests from the app's own window (`ExTauri.Token`).

          plug ExTauri.Token.Plug                       # every path
          plug ExTauri.Token.Plug, only: ["/api"]       # paths under /api only

      A `GET` carrying `?ex_tauri_token=<token>` (how the shell opens the window)
      gets the cookie and a redirect to the same URL without it. Any other request
      to a guarded path needs the cookie or `Authorization: Bearer <token>`, or it
      is answered 401. Put it before the router (in a Phoenix endpoint, before the
      router plug: LiveView's socket carries the cookie too).
      """

      @behaviour Elixir.Plug
      import Elixir.Plug.Conn
      require Logger

      @param "ex_tauri_token"

      @impl true
      def init(opts), do: %{only: Keyword.get(opts, :only, ["/"])}

      @impl true
      def call(conn, %{only: only}) do
        conn = fetch_query_params(conn)

        cond do
          Map.has_key?(conn.query_params, @param) -> exchange(conn)
          not guarded?(conn.request_path, only) -> conn
          authorized?(conn) -> conn
          true -> deny(conn)
        end
      end

      @doc "The cookie's name: one per port, as browsers share cookies across ports."
      def cookie_name(conn), do: "ex_tauri_#{conn.port}"

      defp exchange(%{method: "GET"} = conn) do
        if ExTauri.Token.valid?(conn.query_params[@param]) do
          query = conn.query_params |> Map.delete(@param) |> URI.encode_query()
          location = if query == "", do: conn.request_path, else: "#{conn.request_path}?#{query}"

          conn
          |> put_resp_cookie(cookie_name(conn), ExTauri.Token.get(),
            http_only: true,
            same_site: "Strict",
            path: "/"
          )
          |> put_resp_header("location", location)
          |> put_resp_header("cache-control", "no-store")
          |> send_resp(303, "")
          |> halt()
        else
          deny(conn)
        end
      end

      defp exchange(conn), do: deny(conn)

      defp guarded?(path, only), do: Enum.any?(only, &under?(path, &1))

      defp under?(_path, "/"), do: true

      defp under?(path, prefix),
        do: path == prefix or String.starts_with?(path, String.trim_trailing(prefix, "/") <> "/")

      defp authorized?(conn) do
        conn = fetch_cookies(conn)

        ExTauri.Token.valid?(conn.cookies[cookie_name(conn)]) or
          ExTauri.Token.valid?(bearer(conn))
      end

      defp bearer(conn) do
        case get_req_header(conn, "authorization") do
          ["Bearer " <> token] -> token
          _ -> nil
        end
      end

      defp deny(conn) do
        hint(conn)
        conn |> send_resp(401, "") |> halt()
      end

      # Without the shell nobody hands the window the token: say where to open the
      # app, once.
      defp hint(conn) do
        unless ExTauri.Token.from_shell?() or :persistent_term.get({__MODULE__, :hinted}, false) do
          :persistent_term.put({__MODULE__, :hinted}, true)

          Logger.warning(
            "ex_tauri: no window token from the shell; open " <>
              "#{conn.scheme}://#{conn.host}:#{conn.port}/?#{@param}=#{ExTauri.Token.get()}"
          )
        end
      end
    end
  end
end
