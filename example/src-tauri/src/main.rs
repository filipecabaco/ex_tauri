// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use tauri_plugin_shell::process::CommandEvent;
use tauri_plugin_shell::ShellExt;

fn main() {
    tauri::Builder::default()
        .plugin(
            tauri_plugin_log::Builder::new()
                .level(tauri_plugin_log::log::LevelFilter::Info)
                .build(),
        )
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_log::Builder::new().build())
        .setup(|app| {
            start_server(app.handle());
            check_server_started();
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn start_server(app: &tauri::AppHandle) {
    let sidecar_command = app
        .shell()
        .sidecar("desktop")
        .expect("failed to setup `desktop` sidecar");

    let (mut rx, mut _child) = sidecar_command
        .spawn()
        .expect("Failed to spawn desktop sidecar");

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
