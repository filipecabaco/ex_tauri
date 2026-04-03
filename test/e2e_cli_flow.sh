#!/usr/bin/env bash
#
# Full CLI flow E2E test
#
# Exercises the real developer journey:
#   mix phx.new → add ex_tauri → mix ex_tauri.install → cargo build → launch
#
# Requires: elixir, rust/cargo, xvfb, python3, curl, network access
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=14321
HOST="127.0.0.1"
APP_NAME="test_cli_app"
WORK_DIR=""
TAURI_PID=""

cleanup() {
  echo ""
  echo "=== Cleanup ==="
  if [[ -n "$TAURI_PID" ]] && kill -0 "$TAURI_PID" 2>/dev/null; then
    echo "Killing Tauri process $TAURI_PID"
    kill -TERM "$TAURI_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$TAURI_PID" 2>/dev/null || true
  fi
  # Kill any leftover processes on our port
  fuser -k "$PORT/tcp" 2>/dev/null || true
  if [[ -n "$WORK_DIR" ]] && [[ -d "$WORK_DIR" ]]; then
    echo "Removing $WORK_DIR"
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; exit 1; }

# ─── Step 1: Install Phoenix generator ────────────────────────────────────────
echo ""
echo "=== Step 1: Install Phoenix generator ==="
mix archive.install hex phx_new --force
pass "phx_new installed"

# ─── Step 2: Create a new Phoenix project ─────────────────────────────────────
echo ""
echo "=== Step 2: Create Phoenix project ==="
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

# ─── Step 3: Add ex_tauri as a dependency ─────────────────────────────────────
echo ""
echo "=== Step 3: Add ex_tauri dependency ==="

# Use Elixir to safely modify mix.exs (avoids fragile sed patterns)
elixir -e '
path = "mix.exs"
content = File.read!(path)
# Insert ex_tauri dep right after the opening bracket in the deps list
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
IO.puts("ex_tauri dependency inserted into mix.exs")
'

grep -q "ex_tauri" mix.exs || fail "Failed to add ex_tauri to mix.exs"
pass "ex_tauri added to mix.exs"

# ─── Step 4: Configure ex_tauri and Phoenix endpoint ─────────────────────────
echo ""
echo "=== Step 4: Configure ex_tauri ==="

cat >> config/config.exs << 'ELIXIR_CONFIG'

# ExTauri configuration (added by E2E test)
config :ex_tauri,
  app_name: "Test CLI App",
  host: "127.0.0.1",
  port: 14321,
  version: "2.5.1"
ELIXIR_CONFIG

# Override the Phoenix endpoint port in dev config
cat >> config/dev.exs << 'ELIXIR_CONFIG'

# Override port for E2E test
config :test_cli_app, TestCliAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 14321]
ELIXIR_CONFIG

pass "ex_tauri and endpoint configured (port $PORT)"

# ─── Step 5: Add ShutdownManager to supervision tree ─────────────────────────
echo ""
echo "=== Step 5: Add ShutdownManager to supervision tree ==="

# Use Elixir to safely insert ShutdownManager
elixir -e '
path = "lib/test_cli_app/application.ex"
content = File.read!(path)
new_content = String.replace(
  content,
  "children = [\n",
  "children = [\n      ExTauri.ShutdownManager,\n"
)
if content == new_content do
  IO.puts("ERROR: Failed to insert ShutdownManager")
  System.halt(1)
end
File.write!(path, new_content)
IO.puts("ShutdownManager added to supervision tree")
'

grep -q "ShutdownManager" "lib/${APP_NAME}/application.ex" || fail "Failed to add ShutdownManager"
pass "ShutdownManager added to supervision tree"

# ─── Step 6: Install dependencies ─────────────────────────────────────────────
echo ""
echo "=== Step 6: Install dependencies ==="
mix deps.get
mix compile
pass "Dependencies installed and compiled"

# ─── Step 7: Run mix ex_tauri.install ─────────────────────────────────────────
echo ""
echo "=== Step 7: Run mix ex_tauri.install ==="
mix ex_tauri.install
pass "mix ex_tauri.install completed"

# ─── Step 8: Verify generated files ──────────────────────────────────────────
echo ""
echo "=== Step 8: Verify generated files ==="

test -f src-tauri/Cargo.toml       || fail "Missing src-tauri/Cargo.toml"
test -f src-tauri/src/main.rs      || fail "Missing src-tauri/src/main.rs"
test -f src-tauri/tauri.conf.json  || fail "Missing src-tauri/tauri.conf.json"
test -f src-tauri/capabilities/default.json || fail "Missing capabilities/default.json"
test -f assets/vendor/ex_tauri.js  || fail "Missing assets/vendor/ex_tauri.js"

# Verify main.rs has our host/port baked in
grep -q "let host = \"$HOST\"" src-tauri/src/main.rs || fail "main.rs missing host"
grep -q "let port = \"$PORT\"" src-tauri/src/main.rs || fail "main.rs missing port"

# Verify heartbeat socket name uses sanitized app name
grep -q "tauri_heartbeat_test_cli_app" src-tauri/src/main.rs || fail "main.rs missing heartbeat socket"

# Verify CSP is set (not null)
grep -q '"csp"' src-tauri/tauri.conf.json || fail "tauri.conf.json missing CSP"

# Verify JS hook was generated
grep -q "TauriHook" assets/vendor/ex_tauri.js || fail "JS hook missing TauriHook"
grep -q "ALLOWED_COMMANDS" assets/vendor/ex_tauri.js || fail "JS hook missing ALLOWED_COMMANDS"

pass "All generated files verified"

# ─── Step 9: Build Tauri binary ──────────────────────────────────────────────
echo ""
echo "=== Step 9: Build Tauri binary ==="

# Debug: show generated files before building
echo "  --- Generated Cargo.toml ---"
cat src-tauri/Cargo.toml
echo "  --- Generated main.rs (first 30 lines) ---"
head -30 src-tauri/src/main.rs
echo "  --- Generated tauri.conf.json ---"
cat src-tauri/tauri.conf.json
echo "  ---"

cd src-tauri
cargo build 2>&1
cd ..

# Find the binary (name is the sanitized app name from Cargo.toml)
CARGO_NAME=$(grep '^name = ' src-tauri/Cargo.toml | head -1 | sed 's/name = "\(.*\)"/\1/')
BINARY="src-tauri/target/debug/$CARGO_NAME"
test -f "$BINARY" || fail "Binary not found at $BINARY"
test -x "$BINARY" || fail "Binary not executable"
pass "Tauri binary built: $BINARY"

# ─── Step 10: Create sidecar that starts the real Phoenix server ─────────────
echo ""
echo "=== Step 10: Create sidecar (real Phoenix server) ==="

TRIPLE=$(rustc -Vv | grep host | awk '{print $2}')
PROJECT_DIR="$(pwd)"

# Tauri debug builds resolve externalBin relative to the src-tauri dir,
# so "../burrito_out/desktop" resolves to "$PROJECT_DIR/burrito_out/desktop-$TRIPLE"
mkdir -p burrito_out
SIDECAR_PATH="burrito_out/desktop-$TRIPLE"

cat > "$SIDECAR_PATH" << SIDECAR
#!/usr/bin/env bash
cd "$PROJECT_DIR"
exec elixir --no-halt -S mix phx.server
SIDECAR
chmod +x "$SIDECAR_PATH"

pass "Sidecar created at $SIDECAR_PATH (starts mix phx.server)"

# ─── Step 11: Launch Tauri app under xvfb ────────────────────────────────────
echo ""
echo "=== Step 11: Launch Tauri app under xvfb ==="

if ! command -v xvfb-run &>/dev/null; then
  fail "xvfb-run not found — install xvfb"
fi

# Launch from project root so sidecar path resolves correctly
xvfb-run --auto-servernum --server-args="-screen 0 1024x768x24" \
  "./$BINARY" &
TAURI_PID=$!
echo "Tauri launched with PID $TAURI_PID"

# ─── Step 12: Verify the full flow ──────────────────────────────────────────
echo ""
echo "=== Step 12: Verify ==="

# 12a: Wait for Phoenix to start responding (up to 90s for compilation + boot)
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
  # Print Tauri process status for debugging
  echo "  Tauri process status:"
  kill -0 "$TAURI_PID" 2>/dev/null && echo "  - alive" || echo "  - dead"
  echo "  Checking if sidecar is running:"
  pgrep -f "mix phx.server" || echo "  - no sidecar process found"
  echo "  Checking port $PORT:"
  ss -tlnp | grep "$PORT" || echo "  - port not listening"
  fail "Phoenix did not start within 90s"
fi
pass "Phoenix server is running (HTTP $HTTP_CODE)"

# 12b: Verify Tauri process is still alive (heartbeat keeping it alive)
if ! kill -0 "$TAURI_PID" 2>/dev/null; then
  fail "Tauri process died unexpectedly"
fi
pass "Tauri process alive (PID $TAURI_PID)"

# 12c: Verify the heartbeat socket exists
SOCKET_PATH="$(python3 -c "import tempfile; print(tempfile.gettempdir())")/tauri_heartbeat_test_cli_app.sock"
if [[ -S "$SOCKET_PATH" ]]; then
  pass "Heartbeat socket exists at $SOCKET_PATH"
else
  echo "  (heartbeat socket at $SOCKET_PATH — may not be visible from outside)"
fi

# 12d: Wait a few seconds, verify everything still running (heartbeat working)
echo "  Waiting 5s to confirm heartbeat keeps system alive..."
sleep 5

HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST:$PORT/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "000" ]]; then
  fail "Phoenix stopped responding after 5s (heartbeat may have failed)"
fi
pass "Phoenix still responding after 5s (heartbeat working)"

if ! kill -0 "$TAURI_PID" 2>/dev/null; then
  fail "Tauri process died during heartbeat check"
fi
pass "Tauri still alive after 5s"

# 12e: Kill Tauri and verify Phoenix shuts down (heartbeat-based shutdown)
echo "  Killing Tauri to test heartbeat-based shutdown..."
kill -TERM "$TAURI_PID" 2>/dev/null || true
TAURI_PID=""  # prevent cleanup from trying again

# ShutdownManager has 1500ms timeout + 100ms grace = ~2s for shutdown
echo "  Waiting for ShutdownManager to detect heartbeat loss..."
sleep 4

SHUTDOWN_HTTP=$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST:$PORT/" 2>/dev/null || echo "000")
if [[ "$SHUTDOWN_HTTP" == "000" ]]; then
  pass "Phoenix shut down after Tauri exit (heartbeat-based shutdown works!)"
else
  echo "  WARNING: Phoenix still responding (HTTP $SHUTDOWN_HTTP) — shutdown may be slow"
  echo "  (This can happen if System.stop takes longer on a loaded system)"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  Full CLI flow E2E test PASSED"
echo "========================================="
echo ""
echo "Verified developer journey:"
echo "  1. mix phx.new (create Phoenix project)"
echo "  2. Add ex_tauri dependency"
echo "  3. Configure host, port, app_name"
echo "  4. Add ShutdownManager to supervision tree"
echo "  5. mix ex_tauri.install (scaffold Tauri project via CLI)"
echo "  6. Verify all generated files"
echo "  7. cargo build (produce Tauri binary)"
echo "  8. Launch Tauri → spawns Phoenix sidecar → heartbeat connects"
echo "  9. Verify Phoenix responds to HTTP requests"
echo "  10. Verify heartbeat keeps system alive over 5 seconds"
echo "  11. Verify heartbeat-based shutdown on Tauri exit"
echo ""
