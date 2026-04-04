defmodule ExTauri.Install.Helpers do
  @moduledoc false
  # Shared helper functions for Tauri project setup.

  @main_rs_template Path.join(:code.priv_dir(:ex_tauri), "templates/main.rs.eex")
  @external_resource @main_rs_template

  @doc """
  Installs the Tauri CLI via cargo and initializes the Tauri project structure.
  """
  def setup_tauri_project(args \\ []) do
    validate_prerequisites!()

    config = read_config!()

    install_tauri_cli(config.version, config.installation_path)
    init_tauri_project(config, args)
    generate_rust_files(config)
    configure_tauri_json(config)
    generate_capabilities()
    generate_js_hook()
    inject_js_hook()
    inject_layout_hook()

    :ok
  end

  # ── Config reading ─────────────────────────────────────────────────────────

  defp read_config! do
    app_name = Application.get_env(:ex_tauri, :app_name, "Phoenix Application")

    host =
      Application.get_env(:ex_tauri, :host) ||
        raise """
        :host is not configured. Add to your config/config.exs:

            config :ex_tauri, host: "localhost"
        """

    port =
      Application.get_env(:ex_tauri, :port) ||
        raise """
        :port is not configured. Add to your config/config.exs:

            config :ex_tauri, port: 4000
        """

    %{
      app_name: app_name,
      sanitized_name: ExTauri.Paths.sanitize_name(app_name),
      window_title: Application.get_env(:ex_tauri, :window_title, app_name),
      scheme: Application.get_env(:ex_tauri, :scheme) || "http",
      host: host,
      port: port,
      version: Application.get_env(:ex_tauri, :version) || ExTauri.latest_version(),
      fullscreen: Application.get_env(:ex_tauri, :fullscreen, false),
      height: Application.get_env(:ex_tauri, :height, 600),
      width: Application.get_env(:ex_tauri, :width, 800),
      resize: Application.get_env(:ex_tauri, :resize, true),
      installation_path: ExTauri.installation_path()
    }
  end

  # ── Tauri CLI installation ─────────────────────────────────────────────────

  defp install_tauri_cli(version, installation_path) do
    File.mkdir_p!(installation_path)

    cmd_opts = [
      cd: installation_path,
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    ]

    System.cmd("cargo", build_cli_install_args(version), cmd_opts)
  end

  defp init_tauri_project(config, extra_args) do
    dev_url = "#{config.scheme}://#{config.host}:#{config.port}"

    tauri_args =
      [
        "init",
        "--app-name", config.sanitized_name,
        "--window-title", config.window_title,
        "--dev-url", dev_url,
        "--frontend-dist", dev_url,
        "--directory", File.cwd!(),
        "--tauri-path", File.cwd!(),
        "--before-dev-command", "",
        "--before-build-command", ""
      ] ++ extra_args

    cmd_opts = [into: IO.stream(:stdio, :line), stderr_to_stdout: true]

    {_output, exit_code} =
      Path.join([config.installation_path, "bin", "cargo-tauri"])
      |> System.cmd(tauri_args, cmd_opts)

    unless exit_code == 0 do
      raise "tauri unable to install. exited with status #{exit_code}"
    end
  end

  # ── Rust file generation ───────────────────────────────────────────────────

  defp generate_rust_files(config) do
    src_tauri = Path.join(File.cwd!(), "src-tauri")

    File.write!(
      Path.join(src_tauri, "Cargo.toml"),
      cargo_toml(config.app_name, config.version)
    )

    File.write!(
      Path.join([src_tauri, "src", "main.rs"]),
      main_src(config.host, config.port, config.sanitized_name)
    )
  end

  # ── Tauri JSON configuration ───────────────────────────────────────────────

  defp configure_tauri_json(config) do
    conf_path = Path.join([File.cwd!(), "src-tauri", "tauri.conf.json"])
    identifier = config.sanitized_name |> String.replace("_", "-")

    tauri_conf =
      conf_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.merge(%{
        "productName" => config.app_name,
        "identifier" => "you.app.#{identifier}"
      })
      |> put_in(["bundle", "externalBin"], ["../burrito_out/desktop"])
      |> put_in(["app", "security"], %{
        "csp" =>
          "default-src 'self'; script-src 'self' 'unsafe-inline'; " <>
            "style-src 'self' 'unsafe-inline'; " <>
            "connect-src 'self' ipc: tauri: ws: wss:; " <>
            "img-src 'self' data: asset: tauri:; " <>
            "font-src 'self' data:"
      })
      |> put_in(["app", "windows"], [
        %{
          title: config.window_title,
          fullscreen: config.fullscreen,
          width: config.width,
          height: config.height,
          resizable: config.resize
        }
      ])

    # Merge updater config if enabled
    tauri_conf =
      case ExTauri.Updater.tauri_config() do
        config when config == %{} -> tauri_conf
        updater_config -> Map.merge(tauri_conf, updater_config)
      end

    tauri_conf
    |> Jason.encode!(pretty: true)
    |> then(&File.write!(conf_path, &1))
  end

  # ── Capabilities and JS hook generation ────────────────────────────────────

  defp generate_capabilities do
    capabilities_dir = Path.join([File.cwd!(), "src-tauri", "capabilities"])
    File.mkdir_p!(capabilities_dir)
    File.write!(Path.join(capabilities_dir, "default.json"), capabilities_json())
  end

  defp generate_js_hook do
    vendor_dir = Path.join([File.cwd!(), "assets", "vendor"])
    File.mkdir_p!(vendor_dir)
    File.write!(Path.join(vendor_dir, "ex_tauri.js"), ExTauri.Hook.js_source())
  end

  # ── JS and layout auto-injection ───────────────────────────────────────────

  @doc false
  def inject_js_hook do
    app_js_path = Path.join([File.cwd!(), "assets", "js", "app.js"])

    if File.exists?(app_js_path) do
      content = File.read!(app_js_path)

      if String.contains?(content, "TauriHook") do
        Mix.shell().info("TauriHook already present in app.js, skipping injection")
      else
        content =
          content
          |> inject_tauri_import()
          |> inject_tauri_hooks()

        File.write!(app_js_path, content)
        Mix.shell().info("Injected TauriHook into assets/js/app.js")
      end
    else
      Mix.shell().info("""
      Could not find assets/js/app.js — skipping JS hook injection.
      Add manually:

          import { TauriHook } from "../vendor/ex_tauri"

          let liveSocket = new LiveSocket("/live", Socket, {
            hooks: { TauriHook },
          })
      """)
    end
  end

  defp inject_tauri_import(content) do
    import_line = ~s|import { TauriHook } from "../vendor/ex_tauri"\n|

    case Regex.scan(~r/^import .+$/m, content, return: :index) do
      [] ->
        import_line <> content

      matches ->
        {last_pos, last_len} = matches |> List.last() |> List.first()
        insert_at = last_pos + last_len

        String.slice(content, 0, insert_at) <>
          "\n" <> import_line <>
          String.slice(content, insert_at..-1//1)
    end
  end

  defp inject_tauri_hooks(content) do
    cond do
      content =~ ~r/hooks:\s*\{/ ->
        Regex.replace(~r/(hooks:\s*\{)/, content, "\\1 TauriHook,", global: false)

      content =~ ~r/new LiveSocket\([^)]*\{/ ->
        Regex.replace(
          ~r/(new LiveSocket\([^{]*\{)/,
          content,
          "\\1\n  hooks: { TauriHook },",
          global: false
        )

      true ->
        Mix.shell().info("""
        Could not auto-register TauriHook in LiveSocket.
        Add manually to your LiveSocket constructor:

            hooks: { TauriHook },
        """)

        content
    end
  end

  @doc false
  def inject_layout_hook do
    layout_patterns = [
      Path.join([File.cwd!(), "lib", "*_web", "components", "layouts", "root.html.heex"]),
      Path.join([File.cwd!(), "lib", "*_web", "templates", "layout", "root.html.heex"])
    ]

    layout_path =
      Enum.find_value(layout_patterns, fn pattern ->
        case Path.wildcard(pattern) do
          [path | _] -> path
          [] -> nil
        end
      end)

    case layout_path do
      nil ->
        Mix.shell().info("""
        Could not find root layout template — skipping hook element injection.
        Add manually to your root.html.heex:

            <div id="tauri-bridge" phx-hook="TauriHook"></div>
        """)

      path ->
        inject_layout_hook_into(path)
    end
  end

  defp inject_layout_hook_into(path) do
    content = File.read!(path)

    if String.contains?(content, "tauri-bridge") do
      Mix.shell().info("tauri-bridge element already present in root layout, skipping")
    else
      case Regex.run(~r/<body[^>]*>/, content, return: :index) do
        [{pos, len}] ->
          insert_at = pos + len
          hook_element = "\n    <div id=\"tauri-bridge\" phx-hook=\"TauriHook\"></div>"

          new_content =
            String.slice(content, 0, insert_at) <>
              hook_element <>
              String.slice(content, insert_at..-1//1)

          File.write!(path, new_content)
          Mix.shell().info("Injected tauri-bridge element into #{Path.relative_to_cwd(path)}")

        _ ->
          Mix.shell().info("""
          Could not find <body> tag in root layout.
          Add manually to your root layout:

              <div id="tauri-bridge" phx-hook="TauriHook"></div>
          """)
      end
    end
  end

  # ── Code generation functions ──────────────────────────────────────────────

  @doc false
  def cargo_toml(app_name, tauri_version) do
    sanitized = ExTauri.Paths.sanitize_name(app_name)
    major = extract_cli_version(tauri_version)

    """
    [package]
    name = "#{sanitized}"
    version = "0.1.0"
    default-run = "#{sanitized}"
    edition = "2021"
    description = ""

    [build-dependencies]
    tauri-build = { version = "#{major}", features = [] }

    [dependencies]
    log = "0.4"
    serde_json = "1.0"
    serde = { version = "1.0", features = ["derive"] }
    tauri = { version = "#{major}", features = [] }
    tauri-plugin-shell = "#{major}"
    tauri-plugin-log = "#{major}"
    tauri-plugin-notification = "#{major}"
    tauri-plugin-single-instance = "#{major}"

    [features]
    # this feature is used for production builds or when `devPath` points to the filesystem and the built-in dev server is disabled.
    # If you use cargo directly instead of tauri's cli you can use this feature flag to switch between tauri's `dev` and `build` modes.
    # DO NOT REMOVE!!
    custom-protocol = [ "tauri/custom-protocol" ]
    """
  end

  @doc false
  def main_src(host, port, socket_name) do
    validate_rust_interpolations!(host, port, socket_name)

    EEx.eval_file(@main_rs_template,
      host: to_string(host),
      port: to_string(port),
      socket_name: to_string(socket_name)
    )
  end

  defp validate_rust_interpolations!(host, port, socket_name) do
    unless to_string(host) =~ ~r/\A[a-zA-Z0-9\.\-]+\z/ do
      raise ArgumentError, "host contains invalid characters: #{inspect(host)}"
    end

    unless to_string(port) =~ ~r/\A\d+\z/ do
      raise ArgumentError, "port must be numeric, got: #{inspect(port)}"
    end

    unless to_string(socket_name) =~ ~r/\A[a-zA-Z0-9_\-]+\z/ do
      raise ArgumentError, "socket_name contains invalid characters: #{inspect(socket_name)}"
    end
  end

  @doc false
  def capabilities_json do
    """
    {
      "$schema": "../gen/schemas/desktop-schema.json",
      "identifier": "default",
      "description": "Capability for the main application window",
      "windows": ["main"],
      "permissions": [
        "notification:default",
        {
          "identifier": "shell:allow-execute",
          "allow": [
            {
              "name": "desktop",
              "sidecar": true
            }
          ]
        }
      ]
    }
    """
  end

  @doc false
  def extract_cli_version(tauri_version) do
    case Version.parse(String.replace(tauri_version, ~r/^[^\d]+/, "")) do
      {:ok, v} -> to_string(v.major)
      :error -> tauri_version
    end
  end

  @doc false
  def build_cli_install_args(tauri_version) do
    cli_version = extract_cli_version(tauri_version)
    ["install", "tauri-cli", "--version", "^#{cli_version}", "--root", "."]
  end

  defp validate_prerequisites! do
    unless System.find_executable("cargo") do
      raise """
      Rust/Cargo is not installed or not in your PATH.

      Install Rust: https://www.rust-lang.org/tools/install

          curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

      Then restart your terminal and try again.
      """
    end

    unless System.find_executable("rustc") do
      raise """
      rustc is not installed or not in your PATH.

      Install Rust: https://www.rust-lang.org/tools/install
      """
    end
  end
end
