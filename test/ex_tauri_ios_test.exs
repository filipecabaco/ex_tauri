defmodule ExTauri.IosTest do
  use ExUnit.Case, async: true

  alias ExTauri.Ios

  # What `cargo tauri init` leaves in src/lib.rs, verbatim from an app made with
  # ex_tauri: a mobile entry point nothing calls.
  @tauri_stub """
  #[cfg_attr(mobile, tauri::mobile_entry_point)]
  pub fn run() {
    tauri::Builder::default()
      .setup(|app| {
        if cfg!(debug_assertions) {
          app.handle().plugin(
            tauri_plugin_log::Builder::default()
              .level(log::LevelFilter::Info)
              .build(),
          )?;
        }
        Ok(())
      })
      .run(tauri::generate_context!())
      .expect("error while running tauri application");
  }
  """

  # The shape `mix ex_tauri.install` generates.
  @cargo_toml """
  [package]
  name = "dyson_robot"
  version = "0.4.2"
  edition = "2021"

  [build-dependencies]
  tauri-build = { version = "2", features = [] }

  [dependencies]
  tauri = { version = "2", features = ["tray-icon"] }
  tauri-plugin-shell = "2.5"
  tauri-plugin-single-instance = "2"

  [target.'cfg(target_os = "macos")'.dependencies]
  objc2 = "0.6"

  [features]
  custom-protocol = [ "tauri/custom-protocol" ]
  """

  describe "lib_rs_action/1" do
    test "writes when there is none, over Tauri's stub, and over its own" do
      assert :write = Ios.lib_rs_action(nil)
      assert :write = Ios.lib_rs_action(@tauri_stub)
      assert :write = Ios.lib_rs_action(ExTauri.Install.Helpers.mobile_src("localhost"))
    end

    test "leaves a lib.rs with code of its own alone" do
      own = @tauri_stub <> String.duplicate("\nfn helper() {}\n", 30)

      assert {:refuse, message} = Ios.lib_rs_action(own)
      assert message =~ "--force"
      assert {:refuse, _} = Ios.lib_rs_action("pub fn shared_logic() {}\n")
    end
  end

  describe "mobile_cargo_toml/1" do
    test "adds the lib the iOS build links, named apart from the desktop binary" do
      toml = Ios.mobile_cargo_toml(@cargo_toml)

      assert toml =~ """
             [lib]
             name = "dyson_robot_lib"
             crate-type = ["staticlib", "cdylib", "rlib"]

             [build-dependencies]
             """
    end

    test "moves single-instance to a desktop-only table, since it does not build for iOS" do
      toml = Ios.mobile_cargo_toml(@cargo_toml)

      [deps, desktop] =
        String.split(
          toml,
          ~s{[target.'cfg(not(any(target_os = "android", target_os = "ios")))'.dependencies]}
        )

      refute deps =~ "tauri-plugin-single-instance"
      assert desktop =~ ~s|tauri-plugin-single-instance = "2"|
      # Everything else stays where it was.
      assert deps =~ ~s|tauri-plugin-shell = "2.5"|
      assert deps =~ "objc2"
    end

    test "is idempotent" do
      once = Ios.mobile_cargo_toml(@cargo_toml)
      assert Ios.mobile_cargo_toml(once) == once
    end

    test "leaves a Cargo.toml without the plugin or with its own [lib] alone where it should" do
      toml =
        @cargo_toml
        |> String.replace(~s|tauri-plugin-single-instance = "2"\n|, "")
        |> String.replace(
          "[build-dependencies]",
          "[lib]\nname = \"mine\"\n\n[build-dependencies]"
        )

      assert Ios.mobile_cargo_toml(toml) == toml
    end
  end

  describe "ios_conf/1" do
    test "bundles the backend as a resource instead of a sidecar" do
      conf = Ios.ios_conf(%{"identifier" => "app.markdn.desktop"})

      assert %{
               "build" => %{"frontendDist" => "mobile"},
               "bundle" => %{
                 "externalBin" => [],
                 "resources" => %{"../burrito_out/ios/backend" => "ex_tauri/backend"}
               }
             } = conf

      refute Map.has_key?(conf, "identifier")
      assert Ios.bundle_id(%{"identifier" => "app.markdn.desktop"}, conf) == "app.markdn.desktop"
    end

    test "pins the iOS minimum, which an older Tauri CLI sets below what Xcode builds" do
      assert %{"bundle" => %{"iOS" => %{"minimumSystemVersion" => "15.0"}}} =
               Ios.ios_conf(%{"identifier" => "app.markdn.desktop"})
    end

    test "raises an older project's minimum, and leaves a higher one alone" do
      yml = "options:\n  deploymentTarget:\n    iOS: 14.0\n"
      assert Ios.raise_deployment_target(yml) =~ "iOS: 15.0"

      pbx = "IPHONEOS_DEPLOYMENT_TARGET = 14.0;\nIPHONEOS_DEPLOYMENT_TARGET = 14.0;"

      assert Ios.raise_deployment_target(pbx) ==
               "IPHONEOS_DEPLOYMENT_TARGET = 15.0;\nIPHONEOS_DEPLOYMENT_TARGET = 15.0;"

      assert Ios.raise_deployment_target("IPHONEOS_DEPLOYMENT_TARGET = 16.4;") ==
               "IPHONEOS_DEPLOYMENT_TARGET = 16.4;"
    end

    test "gives iOS an identifier it accepts" do
      conf = Ios.ios_conf(%{"identifier" => "you.app.my_app"})

      assert conf["identifier"] == "you.app.my-app"
      assert Ios.bundle_id(%{"identifier" => "you.app.my_app"}, conf) == "you.app.my-app"
    end
  end

  describe "simulator_target/1" do
    test "packs for the Mac's own architecture, which the simulator runs" do
      assert {:ok, "aarch64-sim"} = Ios.simulator_target("aarch64-apple-darwin")
      assert {:ok, "x86_64"} = Ios.simulator_target("x86_64-apple-darwin")
      assert {:error, _} = Ios.simulator_target("x86_64-unknown-linux-gnu")
    end
  end

  describe "pick_device/2" do
    @devices %{
      "devices" => %{
        "com.apple.CoreSimulator.SimRuntime.watchOS-11-0" => [
          %{"name" => "Apple Watch", "udid" => "W", "state" => "Booted"}
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-26-5" => [
          %{"name" => "iPhone 17 Pro", "udid" => "P", "state" => "Shutdown"},
          %{"name" => "iPad Pro 11-inch (M5)", "udid" => "A", "state" => "Shutdown"}
        ]
      }
    }

    test "takes the one asked for, by name or UDID" do
      assert {:ok, %{"udid" => "P"}} = Ios.pick_device(@devices, "iPhone 17 Pro")
      assert {:ok, %{"udid" => "A"}} = Ios.pick_device(@devices, "A")
    end

    test "otherwise one already booted, else the first iPad" do
      assert {:ok, %{"udid" => "A"}} = Ios.pick_device(@devices, nil)

      booted =
        update_in(@devices, ["devices", "com.apple.CoreSimulator.SimRuntime.iOS-26-5"], fn [p, a] ->
          [%{p | "state" => "Booted"}, a]
        end)

      assert {:ok, %{"udid" => "P"}} = Ios.pick_device(booted, nil)
    end

    test "never picks a watch, and says what there is" do
      assert {:error, message} = Ios.pick_device(@devices, "Apple Watch")
      assert message =~ "iPhone 17 Pro"
    end
  end

  describe "the simulator runtime check" do
    @runtimes %{
      "runtimes" => [
        %{
          "identifier" => "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
          "version" => "26.5",
          "isAvailable" => true
        },
        %{
          "identifier" => "com.apple.CoreSimulator.SimRuntime.tvOS-27-0",
          "version" => "27.0",
          "isAvailable" => true
        }
      ]
    }

    test "passes when an iOS runtime is at least the SDK" do
      assert Ios.runtime_covers_sdk?(@runtimes, "26.5")
      assert Ios.runtime_covers_sdk?(@runtimes, "26.4")
    end

    test "fails when only an older iOS runtime is installed, whatever tvOS has" do
      refute Ios.runtime_covers_sdk?(@runtimes, "27.1")
      assert Ios.newest_runtime(@runtimes) == "26.5"
    end

    test "the shim reports that runtime as the SDK to the one query that checks" do
      shim = Ios.xcrun_shim("26.5", "27.1")

      assert shim =~ ~s|if [ "$*" = "simctl list runtimes --json" ]|
      assert shim =~ ~s|s/"version" : "26.5"/"version" : "27.1"/|
      assert shim =~ ~s|exec /usr/bin/xcrun "$@"|
    end
  end
end
