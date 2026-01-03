// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use tauri::Manager;
use tauri_plugin_shell::process::CommandEvent;
use tauri_plugin_shell::ShellExt;

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
        .plugin(
            tauri_plugin_log::Builder::new()
                .level(tauri_plugin_log::log::LevelFilter::Info)
                .build(),
        )
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
    let sidecar_command = app
        .shell()
        .sidecar("desktop")
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
    let host = "localhost".to_string();
    let port = "4000".to_string();
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

        let socket_path = "/tmp/tauri_heartbeat.sock";
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
