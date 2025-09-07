defmodule ExTauri do
  @latest_version "2.5.1"

  @arg_names %{
    dev_url: %{
      1 => "--dev-path",
      2 => "--dev-url"
    },
    frontend_dist: %{
      1 => "--dist-dir",
      2 => "--frontend-dist"
    }
  }

  @config_keys %{
    productName: %{
      1 => ["package", "productName"],
      2 => ["productName"]
    },
    externalBin: %{
      1 => ["tauri", "bundle", "externalBin"],
      2 => ["bundle", "externalBin"]
    },
    identifier: %{
      1 => ["tauri", "bundle", "identifier"],
      2 => ["identifier"]
    },
    windows: %{
      1 => ["tauri", "windows"],
      2 => ["app", "windows"]
    }
  }

  use Application
  require Logger
  @doc false
  def start(_, _) do
    unless Application.get_env(:ex_tauri, :version) do
      Logger.warning("""
      tauri version is not configured. Please set it in your config files:

          config :ex_tauri, :version, "#{latest_version()}"
      """)
    end

    Supervisor.start_link([], strategy: :one_for_one)
  end

  @doc """
  Returns the latest version of tauri available.
  """
  def latest_version, do: @latest_version

  def get_major(version) do
    case Version.parse(
           version
           |> String.trim()
           |> String.replace(~r/^[^\d]+/, "")
         ) do
      {:ok, %Version{major: major}} ->
        {:ok, major}

      :error ->
        {:error, "Failed to parse version from string '#{version}'."}
    end
  end

  def install(extra_args \\ []) do
    app_name = Application.get_env(:ex_tauri, :app_name, "Phoenix Application")
    window_title = Application.get_env(:ex_tauri, :window_title, app_name)
    scheme = Application.get_env(:ex_tauri, :scheme) || "http"
    host = Application.get_env(:ex_tauri, :host) || raise "Expected :host to be configured"
    port = Application.get_env(:ex_tauri, :port) || raise "Expected :port to be configured"
    version = Application.get_env(:ex_tauri, :version) || latest_version()
    fullscreen = Application.get_env(:ex_tauri, :fullscreen, false)
    height = Application.get_env(:ex_tauri, :height, 600)
    width = Application.get_env(:ex_tauri, :width, 800)
    resize = Application.get_env(:ex_tauri, :resize, true)
    installation_path = installation_path()
    File.mkdir_p!(installation_path)

    {:ok, major} = get_major(version)

    opts = [
      cd: installation_path,
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    ]

    System.cmd("cargo", ["install", "tauri-cli@#{version}", "--root", "."], opts)

    args =
      [
        "init",
        "--app-name",
        app_name |> String.replace("\s", "") |> Macro.underscore(),
        "--window-title",
        window_title,
        @arg_names.dev_url[major],
        "#{scheme}://#{host}:#{port}",
        @arg_names.frontend_dist[major],
        "#{scheme}://#{host}:#{port}",
        "--directory",
        File.cwd!(),
        "--tauri-path",
        File.cwd!(),
        "--before-dev-command",
        "",
        "--before-build-command",
        ""
      ] ++ extra_args

    opts = [
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    ]

    res =
      Path.join([installation_path, "bin", "cargo-tauri"])
      |> System.cmd(args, opts)
      |> elem(1)

    case res do
      0 -> :ok
      _ -> raise "tauri unable to install. exited with status #{res}"
    end

    # Override Cargo.toml to use app_name and set proper crates so they are not dependent on folders
    path = Path.join([File.cwd!(), "src-tauri", "Cargo.toml"])
    File.write!(path, cargo_toml(app_name, version, major))

    # Override main.rs to set proper startup sequence
    path = Path.join([File.cwd!(), "src-tauri", "src", "main.rs"])
    File.write!(path, main_src(host, port, major))

    # TODO remove this when possible, for some reason it's failing at the moment
    File.cp!(
      Path.join([File.cwd!(), "src-tauri", "build.rs"]),
      Path.join([File.cwd!(), "src-tauri", "src", "build.rs"])
    )

    # Add side car and required configuration to tauri.conf.json
    Path.join([File.cwd!(), "src-tauri", "tauri.conf.json"])
    |> File.read!()
    |> Jason.decode!()
    |> then(fn content ->
      content
      |> put_in(@config_keys.productName[major], app_name)
      |> put_in(@config_keys.externalBin[major], ["../burrito_out/desktop"])
      |> put_in(
        @config_keys.identifier[major],
        "you.app.#{app_name |> String.replace("\s", "") |> Macro.underscore() |> String.replace("_", "-")}"
      )
      |> then(fn content ->
        case major do
          1 ->
            content
            |> put_in(["tauri", "allowlist"], %{
              shell: %{
                sidecar: true,
                scope: [%{name: "../burrito_out/desktop", sidecar: true, args: ["start"]}]
              }
            })

          2 ->
            content
        end
      end)
      |> put_in(@config_keys.windows[major], [
        %{
          title: window_title,
          fullscreen: fullscreen,
          width: width,
          height: height,
          resizable: resize
        }
      ])
    end)
    |> Jason.encode!(pretty: true)
    |> then(&File.write!(Path.join([File.cwd!(), "src-tauri", "tauri.conf.json"]), &1))

    case major do
      2 ->
        {_, 0} =
          Path.join([installation_path, "bin", "cargo-tauri"])
          |> System.cmd(["add", "log"], opts)

        {_, 0} =
          Path.join([installation_path, "bin", "cargo-tauri"])
          |> System.cmd(["add", "shell"], opts)

      _ ->
        nil
    end
  end

  @doc """
  Returns the path to the executable.

  The executable may not be available if it was not yet installed.
  """
  def installation_path do
    Application.get_env(:ex_tauri, :path) ||
      if Code.ensure_loaded?(Mix.Project) do
        Path.join(Path.dirname(Mix.Project.build_path()), "_tauri")
      else
        Path.expand("_build/_tauri")
      end
  end

  @doc """
  Installs, if not available, and then runs `tailwind`.

  Returns the same as `run/2`.
  """
  def install_and_run(args) do
    unless File.exists?(installation_path()) do
      install(args)
    end

    run(args)
  end

  @doc """
  Runs the given command with `args`.

  The given args will be appended to the configured args.
  The task output will be streamed directly to stdio. It
  returns the status of the underlying call.
  """
  def run(args) when is_list(args) do
    wrap()

    # Set proper environment variables for tauri
    System.put_env("TAURI_SKIP_DEVSERVER_CHECK", "true")
    # Tauri v2 rename
    System.put_env("TAURI_CLI_NO_DEV_SERVER_WAIT", "true")

    opts = [
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    ]

    {_, 0} =
      [installation_path(), "bin", "cargo-tauri"]
      |> Path.join()
      |> System.cmd(args, opts)
  end

  defp wrap() do
    File.rm_rf!(Path.join([Path.expand("~"), "Library", "Application Support", ".burrito"]))

    get_in(Mix.Project.config(), [:releases, :desktop]) ||
      raise "expected a burrito release configured for the app :desktop in your mix.exs"

    Mix.Task.run("release", ["desktop"])

    triplet =
      System.cmd("rustc", ["-Vv"])
      |> elem(0)
      |> then(&Regex.run(~r/host: (.*)/, &1))
      |> Enum.at(1)

    File.cp!(
      "burrito_out/desktop_#{triplet}",
      "burrito_out/desktop-#{triplet}"
    )

    :ok
  end

  defp cargo_toml(app_name, tauri_version, major) do
    app_name = app_name |> String.replace("\s", "") |> Macro.underscore()

    """
    [package]
    name = "#{app_name}"
    version = "0.1.0"
    default-run = "#{app_name}"
    edition = "2018"
    build = "src/build.rs"
    description = ""

    [build-dependencies]
    tauri-build = "#{tauri_version}"

    [dependencies]
    log = "0.4"
    serde_json = "1.0"
    serde = { version = "1.0", features = ["derive"] }
    #{case major do
      1 -> ~s(tauri = { version = "#{tauri_version}", features = ["api-all"] })
      2 -> ~s(tauri = { version = "#{tauri_version}" })
    end}

    [features]
    # this feature is used for production builds or when `devPath` points to the filesystem and the built-in dev server is disabled.
    # If you use cargo directly instead of tauri's cli you can use this feature flag to switch between tauri's `dev` and `build` modes.
    # DO NOT REMOVE!!
    custom-protocol = [ "tauri/custom-protocol" ]
    """
  end

  defp main_src(host, port, major) do
    """
    // Prevents additional console window on Windows in release, DO NOT REMOVE!!
    #![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
    #{case major do
      1 -> """
        use tauri::api::process::{Command, CommandEvent};
        """
      2 -> """
        use tauri_plugin_shell::process::CommandEvent;
        use tauri_plugin_shell::ShellExt;
        """
    end}
    fn main() {
        tauri::Builder::default()
    #{case major do
      1 -> """
            .setup(|_app| {
                start_server();
                check_server_started();
                Ok(())
            })
        """
      2 -> """
            .setup(|app| {
                start_server(app.handle());
                check_server_started();
                Ok(())
            })
        """
    end}
            .run(tauri::generate_context!())
            .expect("error while running tauri application");
    }
    #{case major do
      1 -> """
        fn start_server() {
          tauri::async_runtime::spawn(async move {
              let (mut rx, mut _child) = Command::new_sidecar("desktop")
                  .expect("failed to setup `desktop` sidecar")
                  .spawn()
                  .expect("Failed to spawn packaged node");

              while let Some(event) = rx.recv().await {
                  if let CommandEvent::Stdout(line) = event {
                      println!("{}", line);
                  }
              }
          });
        }
        """
      2 -> """
        fn start_server(app: &tauri::AppHandle) {
          let sidecar_command = app.shell().sidecar("desktop")
            .expect("failed to setup `desktop` sidecar");

          let (mut rx, mut _child) = sidecar_command
            .spawn()
            .expect("Failed to spawn packaged node");

          tauri::async_runtime::spawn(async move {
              while let Some(event) = rx.recv().await {
                  if let CommandEvent::Stdout(line_bytes) = event {
                      let line = String::from_utf8_lossy(&line_bytes);
                      println!("{}", line);
                  }
              }
          });
        }
        """
    end}

    fn check_server_started() {
        let sleep_interval = std::time::Duration::from_millis(200);
        let host = "#{host}".to_string();
        let port = "#{port}".to_string();
        let addr = format!("{}:{}", host, port);
        println!(
            "Waiting for your phoenix dev server to start on {}...",
            addr
        );
        loop {
            if std::net::TcpStream::connect(addr.clone()).is_ok() {
               break;
            }
            std::thread::sleep(sleep_interval);
        }
    }

    """
  end
end
