// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use tauri::api::process::{Command, CommandEvent};

fn main() {
    tauri::Builder::default()
        .setup(|_app| {
            start_server();
            check_server_started();
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
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

fn check_server_started() {
    let sleep_interval = std::time::Duration::from_secs(1);
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

