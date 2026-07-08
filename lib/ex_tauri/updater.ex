defmodule ExTauri.Updater do
  @moduledoc """
  Configuration helpers for Tauri's built-in auto-updater.

  The updater allows your desktop application to check for updates,
  download them, and apply them automatically. It uses Tauri's
  `tauri-plugin-updater` under the hood.

  ## Setup

  1. Generate signing keys:

      ```bash
      mix ex_tauri.signer generate
      ```

  2. Configure the updater in your `config/config.exs`:

      ```elixir
      config :ex_tauri,
        updater: [
          enabled: true,
          endpoints: ["https://releases.myapp.com/{{target}}/{{arch}}/{{current_version}}"],
          pubkey: "YOUR_PUBLIC_KEY_HERE"
        ]
      ```

  3. The updater plugin will be automatically included when building with
     `mix ex_tauri.build` if `updater.enabled` is true.

  ## Update Endpoint

  Your endpoint must return a JSON response conforming to Tauri's update
  protocol. The simplest approach is to use GitHub Releases:

      ```elixir
      config :ex_tauri,
        updater: [
          enabled: true,
          endpoints: ["https://github.com/user/repo/releases/latest/download/latest.json"],
          pubkey: "YOUR_PUBLIC_KEY_HERE"
        ]
      ```

  ## Check for Updates from LiveView

  Install the updater plugin (`mix ex_tauri.add updater`), then use `check/1`
  and `install/1`:

      ```elixir
      def handle_event("check_updates", _params, socket) do
        {:noreply, ExTauri.Updater.check(socket)}
      end

      def handle_event("tauri_response", %{"command" => "updater_check", "available" => true} = params, socket) do
        {:noreply, assign(socket, update_version: params["version"], update_available: true)}
      end

      def handle_event("tauri_response", %{"command" => "updater_check"}, socket) do
        {:noreply, assign(socket, :update_available, false)}
      end

      def handle_event("install_update", _params, socket) do
        {:noreply, ExTauri.Updater.install(socket)}
      end
      ```

  After a successful install, relaunch with `ExTauri.App.relaunch/1`
  (requires `mix ex_tauri.add process`).

  For more information, see:
  - https://v2.tauri.app/plugin/updater/
  - `Mix.Tasks.ExTauri.Signer` for key management
  """

  @doc """
  Checks for an available update from your LiveView.

  Requires `tauri-plugin-updater` (`mix ex_tauri.add updater`) and a configured
  endpoint (see module docs). The result arrives as a `"tauri_response"` event:
  `%{"command" => "updater_check", "available" => true, "version" => ..., "notes" => ...}`
  or `%{"command" => "updater_check", "available" => false}`.
  """
  def check(socket) do
    ExTauri.Hook.push_command(socket, "updater_check", %{})
  end

  @doc """
  Downloads and installs the update found by the last `check/1`.

  Completion arrives as a `"tauri_response"` event with
  `%{"command" => "updater_install", "status" => "installed"}`; calling this
  without a prior successful check produces a `"tauri_error"` event.
  """
  def install(socket) do
    ExTauri.Hook.push_command(socket, "updater_install", %{})
  end

  @doc """
  Returns the updater configuration from the application env.
  """
  def config do
    Application.get_env(:ex_tauri, :updater, [])
  end

  @doc """
  Returns whether the updater is enabled.
  """
  def enabled? do
    Keyword.get(config(), :enabled, false)
  end

  @doc """
  Returns the configured update endpoints.
  """
  def endpoints do
    Keyword.get(config(), :endpoints, [])
  end

  @doc """
  Returns the configured public key for update verification.
  """
  def pubkey do
    Keyword.get(config(), :pubkey)
  end

  @doc """
  Returns the Tauri updater configuration as a map suitable for
  merging into `tauri.conf.json`.

  Only returns a non-empty map if the updater is enabled and properly
  configured with at least one endpoint and a public key.
  """
  def tauri_config do
    if enabled?() && pubkey() && endpoints() != [] do
      %{
        "plugins" => %{
          "updater" => %{
            "active" => true,
            "endpoints" => endpoints(),
            "pubkey" => pubkey()
          }
        }
      }
    else
      %{}
    end
  end
end
