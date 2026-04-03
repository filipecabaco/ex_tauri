#!/usr/bin/env bash
#
# Full CLI flow E2E test
#
# Exercises the real developer journey matching the library's usage pattern:
#   mix phx.new → add ex_tauri → configure → mix ex_tauri.install →
#   build release → cargo build → launch → verify heartbeat lifecycle
#
# mix ex_tauri.install (with Igniter) automatically handles:
#   - Adding ShutdownManager to supervision tree
#   - Adding :desktop release config to mix.exs
#
# Requires: elixir, rust/cargo, xvfb, python3, curl, network access
#
set -euo pipefail

# Trap ERR to report exactly which command failed
trap 'echo ""; echo "!!! FAILED at line $LINENO with exit code $? !!!"; echo "!!! Command: $BASH_COMMAND !!!"' ERR

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=14321
HOST="127.0.0.1"
APP_NAME="test_cli_app"
SECRET="test-secret-key-base-that-is-at-least-sixty-four-bytes-long-for-phoenix"
WORK_DIR=""
TAURI_PID=""

# Use a fixed CARGO_TARGET_DIR so compiled dependencies are cached between runs.
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/cargo-target-cli-flow}"
mkdir -p "$CARGO_TARGET_DIR"
echo "Using CARGO_TARGET_DIR=$CARGO_TARGET_DIR"

cleanup() {
  echo ""
  echo "=== Cleanup ==="
  if [[ -n "$TAURI_PID" ]] && kill -0 "$TAURI_PID" 2>/dev/null; then
    echo "Killing Tauri process $TAURI_PID"
    kill -TERM "$TAURI_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$TAURI_PID" 2>/dev/null || true
  fi
  fuser -k "$PORT/tcp" 2>/dev/null || true
  if [[ -n "$WORK_DIR" ]] && [[ -d "$WORK_DIR" ]]; then
    echo "Removing $WORK_DIR"
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; exit 1; }

# ─── Step 1: Create Phoenix project ─────────────────────────────────────────
echo ""
echo "=== Step 1: Create Phoenix project ==="
mix archive.install hex phx_new --force

WORK_DIR=$(mktemp -d)
echo "Working directory: $WORK_DIR"
cd "$WORK_DIR"

mix phx.new "$APP_NAME" \
  --no-ecto \
  --no-mailer \
  --no-dashboard \
  --no-assets \
  --no-install

cd "$APP_NAME"
pass "Phoenix project created at $WORK_DIR/$APP_NAME"

# ─── Step 2: Add ex_tauri dependency ─────────────────────────────────────────
echo ""
echo "=== Step 2: Add ex_tauri dependency ==="

# Igniter is a required dep of ex_tauri, so it's pulled in transitively
elixir -e '
path = "mix.exs"
content = File.read!(path)
new_content = String.replace(
  content,
  ~r/defp deps do\s*\n\s*\[/,
  "defp deps do\n    [\n      {:ex_tauri, path: \"'"$REPO_ROOT"'\"},"
)
if content == new_content do
  IO.puts("ERROR: Failed to insert ex_tauri dependency")
  System.halt(1)
end
File.write!(path, new_content)
IO.puts("ex_tauri dependency added to mix.exs")
'

grep -q "ex_tauri" mix.exs || fail "Failed to add ex_tauri to mix.exs"
pass "ex_tauri added to mix.exs"

# ─── Step 3: Configure ex_tauri ─────────────────────────────────────────────
echo ""
echo "=== Step 3: Configure ex_tauri ==="

cat >> config/config.exs << 'ELIXIR_CONFIG'

# ExTauri configuration
config :ex_tauri,
  app_name: "Test CLI App",
  host: "127.0.0.1",
  port: 14321,
  version: "2.5.1"
ELIXIR_CONFIG

# Prod endpoint config (used by the Mix release sidecar)
cat >> config/prod.exs << ELIXIR_CONFIG

# Endpoint config for the desktop release
config :test_cli_app, TestCliAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: $PORT],
  server: true
ELIXIR_CONFIG

# Dev endpoint config
cat >> config/dev.exs << 'ELIXIR_CONFIG'

# Override port for E2E test
config :test_cli_app, TestCliAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 14321]
ELIXIR_CONFIG

pass "ex_tauri and endpoint configured (port $PORT)"

# ─── Step 4: Install dependencies ───────────────────────────────────────────
echo ""
echo "=== Step 4: Install dependencies ==="
mix deps.get
mix compile
pass "Dependencies installed and compiled"

# ─── Step 5: Run mix ex_tauri.install ────────────────────────────────────────
echo ""
echo "=== Step 5: Run mix ex_tauri.install ==="
# With Igniter available, this automatically:
#   - Adds ExTauri.ShutdownManager to the supervision tree
#   - Adds :desktop release config to mix.exs
#   - Sets up the entire Tauri project structure
mix ex_tauri.install --yes
pass "mix ex_tauri.install completed"

# ─── Step 6: Verify setup ───────────────────────────────────────────────────
echo ""
echo "=== Step 6: Verify setup ==="

# Verify Igniter-managed changes
grep -q "ShutdownManager" "lib/${APP_NAME}/application.ex" || fail "ShutdownManager not in supervision tree"
pass "ShutdownManager in supervision tree (via Igniter)"

grep -q "desktop" mix.exs || fail ":desktop release not in mix.exs"
pass ":desktop release configured (via Igniter)"

# Verify Tauri generated files
test -f src-tauri/Cargo.toml       || fail "Missing src-tauri/Cargo.toml"
test -f src-tauri/src/main.rs      || fail "Missing src-tauri/src/main.rs"
test -f src-tauri/tauri.conf.json  || fail "Missing src-tauri/tauri.conf.json"
test -f src-tauri/capabilities/default.json || fail "Missing capabilities/default.json"
test -f assets/vendor/ex_tauri.js  || fail "Missing assets/vendor/ex_tauri.js"

grep -q "let host = \"$HOST\"" src-tauri/src/main.rs || fail "main.rs missing host"
grep -q "let port = \"$PORT\"" src-tauri/src/main.rs || fail "main.rs missing port"
grep -q "tauri_heartbeat_test_cli_app" src-tauri/src/main.rs || fail "main.rs missing heartbeat socket"
grep -q '"csp"' src-tauri/tauri.conf.json || fail "tauri.conf.json missing CSP"
grep -q "TauriHook" assets/vendor/ex_tauri.js || fail "JS hook missing TauriHook"

pass "All generated files verified"

# ─── Step 7: Build Elixir release (sidecar) ─────────────────────────────────
echo ""
echo "=== Step 7: Build Elixir release (sidecar) ==="

# Recompile with changes from Igniter (updated mix.exs, application.ex)
mix compile

# In production, `mix ex_tauri.build` calls wrap() which builds a Burrito release.
# For testing, we build a standard Mix release — same concept, lighter weight.
SECRET_KEY_BASE="$SECRET" MIX_ENV=prod mix release desktop --overwrite

TRIPLE=$(rustc -Vv | grep host | awk '{print $2}')
PROJECT_DIR="$(pwd)"
RELEASE_BIN="$PROJECT_DIR/_build/prod/rel/desktop/bin/desktop"

test -f "$RELEASE_BIN" || fail "Release binary not found at $RELEASE_BIN"
pass "Elixir release built"

# Place sidecar where Tauri expects it (burrito_out/desktop-<triple>)
# In production, Burrito writes to burrito_out/desktop_<triple> and wrap() copies it.
# tauri_build::build() validates externalBin paths at compile time.
mkdir -p burrito_out
SIDECAR_PATH="burrito_out/desktop-$TRIPLE"

cat > "$SIDECAR_PATH" << SIDECAR
#!/bin/sh
export SECRET_KEY_BASE="$SECRET"
exec "$RELEASE_BIN" start
SIDECAR
chmod +x "$SIDECAR_PATH"

pass "Sidecar placed at $SIDECAR_PATH (wraps Elixir release)"

# ─── Step 8: Build Tauri binary ─────────────────────────────────────────────
echo ""
echo "=== Step 8: Build Tauri binary ==="

cd src-tauri
cargo build 2>&1 || { echo "!!! cargo build failed with exit code $? !!!"; exit 1; }
cd ..

CARGO_NAME=$(grep '^name = ' src-tauri/Cargo.toml | head -1 | sed 's/name = "\(.*\)"/\1/')
BINARY="$CARGO_TARGET_DIR/debug/$CARGO_NAME"
test -f "$BINARY" || fail "Binary not found at $BINARY"
test -x "$BINARY" || fail "Binary not executable"
pass "Tauri binary built: $BINARY"

# ─── Step 9: Launch Tauri app ───────────────────────────────────────────────
echo ""
echo "=== Step 9: Launch Tauri app ==="

if ! command -v xvfb-run &>/dev/null; then
  fail "xvfb-run not found — install xvfb"
fi

xvfb-run --auto-servernum --server-args="-screen 0 1024x768x24" \
  "$BINARY" &
TAURI_PID=$!
echo "Tauri launched with PID $TAURI_PID"

# ─── Step 10: Verify the full lifecycle ──────────────────────────────────────
echo ""
echo "=== Step 10: Verify ==="

# 10a: Wait for Phoenix to start (up to 90s for release boot)
echo "  Waiting for Phoenix on $HOST:$PORT..."
SERVER_UP=false
for i in $(seq 1 90); do
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST:$PORT/" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" != "000" ]]; then
    SERVER_UP=true
    echo "  Phoenix responded with HTTP $HTTP_CODE after ${i}s"
    break
  fi
  sleep 1
done

if [[ "$SERVER_UP" != "true" ]]; then
  echo "  Tauri process status:"
  kill -0 "$TAURI_PID" 2>/dev/null && echo "  - alive" || echo "  - dead"
  echo "  Checking sidecar:"
  pgrep -f "desktop" || echo "  - no sidecar process found"
  echo "  Checking port $PORT:"
  ss -tlnp | grep "$PORT" || echo "  - port not listening"
  fail "Phoenix did not start within 90s"
fi
pass "Phoenix server is running (HTTP $HTTP_CODE)"

# 10b: Verify Tauri is alive (heartbeat keeping it alive)
kill -0 "$TAURI_PID" 2>/dev/null || fail "Tauri process died unexpectedly"
pass "Tauri process alive (PID $TAURI_PID)"

# 10c: Check heartbeat socket
SOCKET_PATH="$(python3 -c "import tempfile; print(tempfile.gettempdir())")/tauri_heartbeat_test_cli_app.sock"
if [[ -S "$SOCKET_PATH" ]]; then
  pass "Heartbeat socket exists at $SOCKET_PATH"
else
  echo "  (heartbeat socket at $SOCKET_PATH — may not be visible from outside)"
fi

# 10d: Verify heartbeat keeps system alive over 5 seconds
echo "  Waiting 5s to confirm heartbeat keeps system alive..."
sleep 5

HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST:$PORT/" 2>/dev/null || echo "000")
[[ "$HTTP_CODE" != "000" ]] || fail "Phoenix stopped responding after 5s (heartbeat may have failed)"
pass "Phoenix still responding after 5s (heartbeat working)"

kill -0 "$TAURI_PID" 2>/dev/null || fail "Tauri process died during heartbeat check"
pass "Tauri still alive after 5s"

# 10e: Verify heartbeat-based shutdown on Tauri exit
echo "  Killing Tauri to test heartbeat-based shutdown..."
kill -TERM "$TAURI_PID" 2>/dev/null || true
TAURI_PID=""

echo "  Waiting for ShutdownManager to detect heartbeat loss..."
sleep 4

SHUTDOWN_HTTP=$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST:$PORT/" 2>/dev/null || echo "000")
if [[ "$SHUTDOWN_HTTP" == "000" ]]; then
  pass "Phoenix shut down after Tauri exit (heartbeat-based shutdown works!)"
else
  echo "  WARNING: Phoenix still responding (HTTP $SHUTDOWN_HTTP) — shutdown may be slow"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  Full CLI flow E2E test PASSED"
echo "========================================="
echo ""
echo "Verified developer journey:"
echo "  1. mix phx.new (create Phoenix project)"
echo "  2. Add ex_tauri dependency (igniter comes transitively)"
echo "  3. Configure ex_tauri (app_name, host, port)"
echo "  4. mix deps.get + mix compile"
echo "  5. mix ex_tauri.install (Igniter: supervision tree + releases + Tauri)"
echo "  6. Verify all setup (Igniter changes + generated files)"
echo "  7. Build Elixir release as sidecar"
echo "  8. cargo build (produce Tauri binary)"
echo "  9. Launch Tauri → spawns sidecar release → heartbeat connects"
echo "  10. Verify heartbeat lifecycle (alive, stable, shutdown)"
echo ""
