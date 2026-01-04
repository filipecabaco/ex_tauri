defmodule ExTauri do
  @latest_version "2.5.1"

  @arg_names %{
    dev_url: "--dev-url",
    frontend_dist: "--frontend-dist"
  }

  @config_keys %{
    productName: ["productName"],
    externalBin: ["bundle", "externalBin"],
    identifier: ["identifier"],
    windows: ["app", "windows"]
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

    opts = [
      cd: installation_path,
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    ]

    # Install tauri-cli using semver range to avoid version mismatch errors
    System.cmd("cargo", build_cli_install_args(version), opts)

    args =
      [
        "init",
        "--app-name",
        app_name |> String.replace("\s", "") |> Macro.underscore(),
        "--window-title",
        window_title,
        @arg_names.dev_url,
        "#{scheme}://#{host}:#{port}",
        @arg_names.frontend_dist,
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
    File.write!(path, cargo_toml(app_name, version))

    # Override main.rs to set proper startup sequence
    path = Path.join([File.cwd!(), "src-tauri", "src", "main.rs"])
    socket_name = app_name |> String.replace(" ", "_") |> String.downcase()
    File.write!(path, main_src(host, port, socket_name))

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
      |> put_in(@config_keys.productName, app_name)
      |> put_in(@config_keys.externalBin, ["../burrito_out/desktop"])
      |> put_in(
        @config_keys.identifier,
        "you.app.#{app_name |> String.replace("\s", "") |> Macro.underscore() |> String.replace("_", "-")}"
      )
      |> put_in(@config_keys.windows, [
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

    # Add plugins for Tauri V2
    {_, 0} =
      Path.join([installation_path, "bin", "cargo-tauri"])
      |> System.cmd(["add", "log"], opts)

    {_, 0} =
      Path.join([installation_path, "bin", "cargo-tauri"])
      |> System.cmd(["add", "shell"], opts)

    # Create capabilities file for Tauri V2
    capabilities_dir = Path.join([File.cwd!(), "src-tauri", "capabilities"])
    File.mkdir_p!(capabilities_dir)
    File.write!(Path.join([capabilities_dir, "default.json"]), capabilities_json())
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
    # Verify we're in a directory with src-tauri before proceeding
    unless File.dir?("src-tauri") do
      raise """
      Could not find src-tauri directory in the current path: #{File.cwd!()}

      Make sure you:
      1. Run this command from your project root (where mix.exs is located)
      2. Have run 'mix ex_tauri.install' to set up the Tauri project structure

      If you're in the ex_tauri repository root, try:
        cd example
        mix ex_tauri build
      """
    end

    wrap()

    opts = [
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true,
      # Run from project root where src-tauri exists
      cd: File.cwd!()
    ]

    case [installation_path(), "bin", "cargo-tauri"]
         |> Path.join()
         |> System.cmd(args, opts) do
      {_, 0} ->
        :ok
      {_, exit_code} ->
        raise """
        Tauri command failed with exit code #{exit_code}.

        Make sure you have a valid Tauri project with src-tauri/tauri.conf.json
        and that all dependencies are properly installed.
        """
    end
  end

  defp wrap() do
    File.rm_rf!(Path.join([Path.expand("~"), "Library", "Application Support", ".burrito"]))

    get_in(Mix.Project.config(), [:releases, :desktop]) ||
      raise "expected a burrito release configured for the app :desktop in your mix.exs"

    # Run release with MIX_ENV=prod at shell level to avoid including dev config with regexes
    # Dev config (like live_reload patterns) contains regexes that can't be serialized
    # Must run as separate process so dependencies are loaded correctly for prod environment
    case System.cmd("mix", ["release", "desktop", "--overwrite"],
      env: [{"MIX_ENV", "prod"}],
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    ) do
      {_, 0} ->
        :ok
      {_, exit_code} ->
        raise """
        Failed to build release with exit code #{exit_code}.

        If you see a Burrito ERTS download error (404), you may need to configure
        a different ERTS version in your mix.exs release configuration.

        See: https://github.com/burrito-elixir/burrito#configuration
        """
    end

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

  defp cargo_toml(app_name, tauri_version) do
    app_name = app_name |> String.replace("\s", "") |> Macro.underscore()

    # Extract major version for plugins (they have independent versioning)
    # e.g., "2.5.1" -> "2", "2.0.0-rc.1" -> "2"
    major_version =
      case Version.parse(String.replace(tauri_version, ~r/^[^\d]+/, "")) do
        {:ok, version} -> to_string(version.major)
        :error -> tauri_version  # Fallback to full version if parsing fails
      end

    """
    [package]
    name = "#{app_name}"
    version = "0.1.0"
    default-run = "#{app_name}"
    edition = "2021"
    build = "src/build.rs"
    description = ""

    [build-dependencies]
    tauri-build = { version = "#{major_version}", features = [] }

    [dependencies]
    log = "0.4"
    serde_json = "1.0"
    serde = { version = "1.0", features = ["derive"] }
    tauri = { version = "#{major_version}", features = [] }
    tauri-plugin-shell = "#{major_version}"
    tauri-plugin-log = "#{major_version}"

    [features]
    # this feature is used for production builds or when `devPath` points to the filesystem and the built-in dev server is disabled.
    # If you use cargo directly instead of tauri's cli you can use this feature flag to switch between tauri's `dev` and `build` modes.
    # DO NOT REMOVE!!
    custom-protocol = [ "tauri/custom-protocol" ]
    """
  end

  defp main_src(host, port, socket_name) do

    """
    // Prevents additional console window on Windows in release, DO NOT REMOVE!!
    #![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
    use tauri_plugin_shell::process::CommandEvent;
    use tauri_plugin_shell::ShellExt;
    use tauri::Manager;

    use std::sync::Mutex;
    use std::time::Duration;

    struct AppState {
        sidecar_child: Mutex<Option<SidecarProcess>>,
    }

    struct SidecarProcess {
        child: Option<tauri_plugin_shell::process::CommandChild>,
        pid: Option<u32>,
    }

    impl Drop for SidecarProcess {
        fn drop(&mut self) {
            if let Some(child) = self.child.take() {
                let _ = child.kill();
            }
        }
    }

    fn kill_sidecar(app: &tauri::AppHandle) {
        if let Some(state) = app.try_state::<AppState>() {
            if let Ok(mut guard) = state.sidecar_child.lock() {
                if let Some(mut process) = guard.take() {
                    // Try graceful shutdown first with SIGTERM
                    if let Some(pid) = process.pid {
                        println!("Attempting graceful shutdown of sidecar (PID: {})...", pid);

                        // Send SIGTERM for graceful shutdown
                        #[cfg(unix)]
                        {
                            use std::process::Command;
                            let _ = Command::new("kill")
                                .args(["-TERM", &pid.to_string()])
                                .output();

                            // Wait up to 2 seconds for graceful shutdown
                            let timeout = Duration::from_millis(2000);
                            let start = std::time::Instant::now();

                            while start.elapsed() < timeout {
                                // Check if process is still running
                                let status = Command::new("kill")
                                    .args(["-0", &pid.to_string()])
                                    .output();

                                if let Ok(output) = status {
                                    if !output.status.success() {
                                        println!("Sidecar shut down gracefully");
                                        return;
                                    }
                                }

                                std::thread::sleep(Duration::from_millis(100));
                            }

                            println!("Graceful shutdown timeout, forcing kill...");
                        }

                        #[cfg(windows)]
                        {
                            // On Windows, wait a bit for graceful shutdown
                            std::thread::sleep(Duration::from_millis(2000));
                        }
                    }

                    // Fallback to SIGKILL if graceful shutdown didn't work
                    if let Some(child) = process.child.take() {
                        println!("Sending SIGKILL to sidecar...");
                        let _ = child.kill();
                    }
                }
            }
        }
    }

    fn main() {
        tauri::Builder::default()
            .plugin(tauri_plugin_shell::init())
            .plugin(tauri_plugin_log::Builder::new().build())
            .manage(AppState {
                sidecar_child: Mutex::new(None),
            })
            .setup(|app| {
                start_server(app.handle());
                check_server_started();
                start_heartbeat();
                Ok(())
            })
            // Intercept menu events (especially CMD+Q on macOS)
            .on_menu_event(|app, event| {
                println!("Menu event received: {:?}", event.id());
                // On macOS, the default menu includes a "quit" item
                // Intercept it to perform graceful shutdown
                if event.id().as_ref() == "quit" || event.id().as_ref().contains("quit") {
                    println!("Quit menu item clicked (CMD+Q), shutting down gracefully...");
                    kill_sidecar(app);
                    std::thread::sleep(std::time::Duration::from_millis(500));
                    std::process::exit(0);
                }
            })
            .on_window_event(|window, event| {
                if let tauri::WindowEvent::CloseRequested { .. } = event {
                    // Kill the sidecar when the window closes
                    kill_sidecar(&window.app_handle());
                }
            })
            .build(tauri::generate_context!())
            .expect("error while building tauri application")
            .run(|app_handle, event| {
                if let tauri::RunEvent::ExitRequested { api, .. } = event {
                    // Kill the sidecar when the app is exiting (fallback for non-menu exits)
                    println!("ExitRequested event received, shutting down...");
                    kill_sidecar(app_handle);
                    api.prevent_exit(); // Prevent exit until we've cleaned up
                    // Allow exit after cleanup
                    std::thread::spawn(move || {
                        std::thread::sleep(std::time::Duration::from_millis(500));
                        std::process::exit(0);
                    });
                }
            });
    }

    fn start_server(app: &tauri::AppHandle) {
        let sidecar_command = app.shell().sidecar("desktop")
            .expect("failed to setup `desktop` sidecar");

        let (mut rx, child) = sidecar_command
            .spawn()
            .expect("Failed to spawn desktop sidecar");

        // Get the PID for graceful shutdown
        let pid = child.pid();
        println!("Sidecar process started with PID: {}", pid);

        // Store the child process handle so we can kill it on exit
        if let Some(state) = app.try_state::<AppState>() {
            if let Ok(mut guard) = state.sidecar_child.lock() {
                *guard = Some(SidecarProcess {
                    child: Some(child),
                    pid: Some(pid),
                });
            }
        }

        tauri::async_runtime::spawn(async move {
            while let Some(event) = rx.recv().await {
                if let CommandEvent::Stdout(line_bytes) = event {
                    let line = String::from_utf8_lossy(&line_bytes);
                    println!("{}", line);
                }
            }
        });
    }

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

    fn start_heartbeat() {
        println!("Starting heartbeat to Phoenix sidecar...");

        std::thread::spawn(|| {
            use std::io::Write;
            use std::os::unix::net::UnixStream;

            let socket_path = "/tmp/tauri_heartbeat_#{socket_name}.sock";
            let interval = Duration::from_millis(100);

            // Wait for socket to be ready
            let mut stream = loop {
                match UnixStream::connect(socket_path) {
                    Ok(s) => break s,
                    Err(_) => {
                        // Socket not ready yet, wait and retry
                        std::thread::sleep(Duration::from_millis(100));
                    }
                }
            };

            println!("Connected to heartbeat socket");

            loop {
                match stream.write_all(b"h") {
                    Ok(_) => {
                        // Heartbeat sent successfully
                    }
                    Err(_) => {
                        // Connection lost, sidecar likely shut down
                        break;
                    }
                }

                std::thread::sleep(interval);
            }
        });
    }

    """
  end

  defp capabilities_json do
    """
    {
      "$schema": "../gen/schemas/desktop-schema.json",
      "identifier": "default",
      "description": "Capability for the main application window",
      "windows": ["main"],
      "permissions": [
        "shell:allow-execute",
        "shell:allow-spawn",
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

  defp extract_cli_version(tauri_version) do
    case Version.parse(String.replace(tauri_version, ~r/^[^\d]+/, "")) do
      {:ok, v} -> to_string(v.major)
      :error -> tauri_version
    end
  end

  defp build_cli_install_args(tauri_version) do
    cli_version = extract_cli_version(tauri_version)
    ["install", "tauri-cli", "--version", "^#{cli_version}", "--root", "."]
  end

  if Mix.env() == :test do
    @doc false
    def __test_cargo_toml__(app_name, tauri_version), do: cargo_toml(app_name, tauri_version)

    @doc false
    def __test_main_src__(host, port, socket_name \\ "app"), do: main_src(host, port, socket_name)

    @doc false
    def __test_capabilities_json__(), do: capabilities_json()

    @doc false
    def __test_extract_cli_version__(tauri_version), do: extract_cli_version(tauri_version)

    @doc false
    def __test_build_cli_install_args__(tauri_version), do: build_cli_install_args(tauri_version)
  end
end
