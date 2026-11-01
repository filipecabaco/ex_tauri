//! ex_tauri's iOS shell plugin: makes the web view behave like an app's. See
//! ios/Sources/ExTauriShell.swift. Registered by `mix ex_tauri.ios init`; its
//! settings come from `config :ex_tauri, :ios`, written to `plugins.ex-tauri` in
//! tauri.ios.conf.json.

use tauri::{
    plugin::{Builder, TauriPlugin},
    Runtime,
};

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_ex_tauri);

pub fn init<R: Runtime>() -> TauriPlugin<R, Option<serde_json::Value>> {
    Builder::<R, Option<serde_json::Value>>::new("ex-tauri")
        .setup(|_app, _api| {
            #[cfg(target_os = "ios")]
            _api.register_ios_plugin(init_plugin_ex_tauri)?;
            Ok(())
        })
        .build()
}
