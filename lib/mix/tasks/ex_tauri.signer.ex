defmodule Mix.Tasks.ExTauri.Signer do
  @moduledoc """
  Manages code signing for Tauri application updates.

  This task helps you generate and manage signing keys for Tauri's built-in
  updater functionality. Code signing ensures that updates to your application
  are authentic and haven't been tampered with.

  ## Usage

      $ mix ex_tauri.signer <SUBCOMMAND> [OPTIONS]

  ## Subcommands

    * `generate` - Generate a new signing key pair
    * `sign` - Sign a file with your private key

  ## Generate Options

    * `--output <DIR>` / `-o <DIR>` - Output directory for the key pair
    * `--password <PASS>` / `-p <PASS>` - Password to protect the private key
    * `--write-keys` / `-w` - Write the keys to tauri.conf.json

  ## Sign Options

    * `--private-key <PATH>` / `-k <PATH>` - Path to the private key
    * `--password <PASS>` / `-p <PASS>` - Password for the private key
    * `--file <PATH>` / `-f <PATH>` - File to sign

  ## Examples

      # Generate a new key pair
      $ mix ex_tauri.signer generate

      # Generate and save to config
      $ mix ex_tauri.signer generate --write-keys

      # Generate with password protection
      $ mix ex_tauri.signer generate --password "my-secret-password"

      # Sign a file
      $ mix ex_tauri.signer sign --file path/to/update.tar.gz --private-key path/to/key.key

      # Sign with password-protected key
      $ mix ex_tauri.signer sign -f update.tar.gz -k key.key -p "my-password"

  ## Workflow

  1. Generate a key pair during initial setup:
     ```
     $ mix ex_tauri.signer generate --write-keys
     ```

  2. Keep your private key secure (add it to .gitignore!)

  3. Sign your update bundles before distribution:
     ```
     $ mix ex_tauri.signer sign -f my-app-update.tar.gz -k ~/.tauri/my-app.key
     ```

  4. Include the signature with your update manifest

  ## Security Notes

  - **NEVER** commit your private key to version control
  - Store private keys securely (use environment variables in CI/CD)
  - Use strong passwords for key protection
  - The public key can be safely included in your repository
  - Distribute the public key with your application

  ## Update Configuration

  After generating keys, update your tauri.conf.json:

  ```json
  {
    "updater": {
      "active": true,
      "pubkey": "YOUR_PUBLIC_KEY_HERE"
    }
  }
  ```

  For more information, see: https://github.com/filipecabaco/ex_tauri
  """

  @shortdoc "Manages code signing for application updates"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run(args) do
    # The signer command has subcommands, so we pass everything through
    ExTauri.run_simple(["signer" | args])
  end
end
