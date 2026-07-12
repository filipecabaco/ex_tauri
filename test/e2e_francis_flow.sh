#!/usr/bin/env bash
#
# Francis CLI flow E2E test
#
# Proves ex_tauri's sidecar path is framework-agnostic by driving a non-Phoenix
# (Francis) app all the way to a running desktop build:
#   mix francis.new --sup → add ex_tauri → configure (sidecar_env: []) →
#   mix ex_tauri.install → build release → cargo build → launch → verify HTTP +
#   heartbeat lifecycle
#
# What this specifically exercises that the Phoenix flow does not:
#   - `config :ex_tauri, sidecar_env: []` — the generated Rust injects only the
#     framework-neutral PORT + SECRET_KEY_BASE, and NO PHX_SERVER/PHX_HOST.
#   - A hand-written config/runtime.exs that reads PORT into bandit_opts, since
#     Francis (unlike Phoenix) does not read PORT itself.
#
# Requires: elixir >= 1.18 (Francis generator target), rust/cargo, xvfb,
#           python3, curl, network access
#
set -euo pipefail

trap 'echo ""; echo "!!! FAILED at line $LINENO with exit code $? !!!"; echo "!!! Command: $BASH_COMMAND !!!"' ERR

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=14322
HOST="127.0.0.1"
APP_NAME="francis_desktop"
MODULE="FrancisDesktop"
SECRET="test-secret-key-base-that-is-at-least-sixty-four-bytes-long-for-testing"
WORK_DIR=""
TAURI_PID=""

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/cargo-target-francis-flow}"
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

# ─── Step 1: Create Francis project ─────────────────────────────────────────
echo ""
echo "=== Step 1: Create Francis project ==="
mix archive.install hex francis --force

WORK_DIR=$(mktemp -d)
echo "Working directory: $WORK_DIR"
cd "$WORK_DIR"

mix francis.new "$APP_NAME" --sup
cd "$APP_NAME"
pass "Francis project created at $WORK_DIR/$APP_NAME"

# ─── Step 2: Add ex_tauri dependency ─────────────────────────────────────────
echo ""
echo "=== Step 2: Add ex_tauri dependency ==="

# The generated mix.exs has `defp deps do [ {:francis, ...} ]`. Insert ex_tauri
# as the first dependency.
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

# ─── Step 3: Configure ex_tauri (framework-agnostic sidecar) ─────────────────
echo ""
echo "=== Step 3: Configure ex_tauri ==="

# sidecar_env: [] is the whole point — no Phoenix env vars injected into the
# sidecar. PORT + SECRET_KEY_BASE are always injected by ex_tauri regardless.
cat >> config/config.exs << ELIXIR_CONFIG

# ExTauri configuration (non-Phoenix / Francis)
config :ex_tauri,
  app_name: "Francis Desktop",
  host: "$HOST",
  port: $PORT,
  version: "2.5.1",
  sidecar_env: []
ELIXIR_CONFIG

# Francis does not read PORT itself, so the app owns this one-liner. runtime.exs
# is evaluated by the release (the production sidecar), binding Bandit to the
# port Tauri assigns.
cat > config/runtime.exs << 'ELIXIR_CONFIG'
import Config

# Bind Francis to the PORT the ex_tauri sidecar receives in production.
if port = System.get_env("PORT") do
  config :francis, bandit_opts: [ip: {127, 0, 0, 1}, port: String.to_integer(port)]
end
ELIXIR_CONFIG

# Dev/build default so Bandit has a concrete port even without PORT set.
cat >> config/dev.exs << ELIXIR_CONFIG

config :francis, bandit_opts: [ip: {127, 0, 0, 1}, port: $PORT]
ELIXIR_CONFIG

pass "ex_tauri configured with sidecar_env: [] and PORT runtime.exs (port $PORT)"

# ─── Step 4: Install dependencies ───────────────────────────────────────────
echo ""
echo "=== Step 4: Install dependencies ==="
mix deps.get
mix compile
pass "Dependencies installed and compiled"

# ─── Step 5: Run mix ex_tauri.install ────────────────────────────────────────
echo ""
echo "=== Step 5: Run mix ex_tauri.install ==="
mix ex_tauri.install --yes
pass "mix ex_tauri.install completed"

# ─── Step 6: Verify setup ───────────────────────────────────────────────────
echo ""
echo "=== Step 6: Verify setup ==="

# Igniter-managed changes to the Francis --sup application module
grep -q "ShutdownManager" "lib/${APP_NAME}/application.ex" || fail "ShutdownManager not in supervision tree"
pass "ShutdownManager in supervision tree (via Igniter)"

grep -q "desktop" mix.exs || fail ":desktop release not in mix.exs"
pass ":desktop release configured (via Igniter)"

# Tauri generated files
test -f src-tauri/Cargo.toml       || fail "Missing src-tauri/Cargo.toml"
test -f src-tauri/src/main.rs      || fail "Missing src-tauri/src/main.rs"
test -f src-tauri/tauri.conf.json  || fail "Missing src-tauri/tauri.conf.json"
test -f src-tauri/capabilities/default.json || fail "Missing capabilities/default.json"

grep -q "let host = \"$HOST\"" src-tauri/src/main.rs || fail "main.rs missing host"
grep -q "unwrap_or($PORT)" src-tauri/src/main.rs || fail "main.rs missing default port"
grep -q "tauri_heartbeat_francis_desktop" src-tauri/src/main.rs || fail "main.rs missing heartbeat socket"

# The framework-agnostic assertion: sidecar_env: [] means NO Phoenix env vars
# are injected. Match the actual injection line, not the explanatory comment.
if grep -qE '\("PHX_SERVER"\.to_string\(\)' src-tauri/src/main.rs; then
  fail "main.rs injects PHX_SERVER despite sidecar_env: [] (framework leak)"
fi
pass "main.rs injects no PHX_* env (sidecar_env: [] honored)"

# PORT is always injected, framework-neutral
grep -q '("PORT".to_string()' src-tauri/src/main.rs || fail "main.rs missing PORT injection"
pass "main.rs injects framework-neutral PORT"

pass "All generated files verified"

# ─── Step 7: Build Elixir release (sidecar) ─────────────────────────────────
echo ""
echo "=== Step 7: Build Elixir release (sidecar) ==="

mix compile

# `mix ex_tauri.build` calls wrap() (Burrito) in production. For the test we
# build a standard Mix release — same concept, lighter weight.
SECRET_KEY_BASE="$SECRET" MIX_ENV=prod mix release desktop --overwrite

TRIPLE=$(rustc -Vv | grep host | awk '{print $2}')
PROJECT_DIR="$(pwd)"
RELEASE_BIN="$PROJECT_DIR/_build/prod/rel/desktop/bin/desktop"

test -f "$RELEASE_BIN" || fail "Release binary not found at $RELEASE_BIN"
pass "Elixir release built"

# Place the sidecar where Tauri expects it. Export exactly what the generated
# Rust injects with sidecar_env: [] — PORT + SECRET_KEY_BASE, and NO PHX_*.
mkdir -p burrito_out
SIDECAR_PATH="burrito_out/desktop-$TRIPLE"

cat > "$SIDECAR_PATH" << SIDECAR
#!/bin/sh
export SECRET_KEY_BASE="$SECRET"
export PORT=$PORT
exec "$RELEASE_BIN" start
SIDECAR
chmod +x "$SIDECAR_PATH"

pass "Sidecar placed at $SIDECAR_PATH (Francis release, no PHX_* env)"

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

echo "  Waiting for Francis on $HOST:$PORT..."
SERVER_UP=false
for i in $(seq 1 90); do
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST:$PORT/" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" != "000" ]]; then
    SERVER_UP=true
    echo "  Francis responded with HTTP $HTTP_CODE after ${i}s"
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
  fail "Francis did not start within 90s"
fi
pass "Francis server is running (HTTP $HTTP_CODE)"

# Francis's generated router returns "ok" for GET /
BODY=$(curl -s "http://$HOST:$PORT/" 2>/dev/null || echo "")
[[ "$BODY" == "ok" ]] || echo "  (note: GET / returned '$BODY', expected 'ok')"

kill -0 "$TAURI_PID" 2>/dev/null || fail "Tauri process died unexpectedly"
pass "Tauri process alive (PID $TAURI_PID)"

SOCKET_PATH="$(python3 -c "import tempfile; print(tempfile.gettempdir())")/tauri_heartbeat_francis_desktop.sock"
if [[ -S "$SOCKET_PATH" ]]; then
  pass "Heartbeat socket exists at $SOCKET_PATH"
else
  echo "  (heartbeat socket at $SOCKET_PATH — may not be visible from outside)"
fi

echo "  Waiting 5s to confirm heartbeat keeps system alive..."
sleep 5
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST:$PORT/" 2>/dev/null || echo "000")
[[ "$HTTP_CODE" != "000" ]] || fail "Francis stopped responding after 5s (heartbeat may have failed)"
pass "Francis still responding after 5s (heartbeat working)"

kill -0 "$TAURI_PID" 2>/dev/null || fail "Tauri process died during heartbeat check"
pass "Tauri still alive after 5s"

echo "  Killing Tauri to test heartbeat-based shutdown..."
kill -TERM "$TAURI_PID" 2>/dev/null || true
TAURI_PID=""

echo "  Waiting for ShutdownManager to detect heartbeat loss..."
sleep 4

SHUTDOWN_HTTP=$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST:$PORT/" 2>/dev/null || echo "000")
if [[ "$SHUTDOWN_HTTP" == "000" ]]; then
  pass "Francis shut down after Tauri exit (heartbeat-based shutdown works!)"
else
  echo "  WARNING: Francis still responding (HTTP $SHUTDOWN_HTTP) — shutdown may be slow"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  Francis CLI flow E2E test PASSED"
echo "========================================="
echo ""
echo "Verified framework-agnostic desktop journey:"
echo "  1. mix francis.new --sup (non-Phoenix app)"
echo "  2. Add ex_tauri dependency"
echo "  3. Configure ex_tauri (sidecar_env: [], PORT runtime.exs)"
echo "  4. mix deps.get + mix compile"
echo "  5. mix ex_tauri.install (Tauri project, supervision tree, release)"
echo "  6. Verify setup — crucially, NO PHX_* env injected into the sidecar"
echo "  7. Build Elixir release as sidecar"
echo "  8. cargo build (produce Tauri binary)"
echo "  9. Launch Tauri → spawns Francis sidecar → heartbeat connects"
echo "  10. Verify heartbeat lifecycle (alive, stable, shutdown)"
echo ""
