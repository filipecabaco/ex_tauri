// swift-tools-version:5.5

import PackageDescription

let package = Package(
  name: "tauri-plugin-ex-tauri",
  platforms: [.iOS(.v15)],
  products: [
    .library(name: "tauri-plugin-ex-tauri", type: .static, targets: ["tauri-plugin-ex-tauri"])
  ],
  dependencies: [
    // Placed here by the plugin's build (tauri-plugin), from the tauri crate.
    .package(name: "Tauri", path: "../.tauri/tauri-api")
  ],
  targets: [
    .target(name: "tauri-plugin-ex-tauri", dependencies: [.byName(name: "Tauri")], path: "Sources")
  ]
)
