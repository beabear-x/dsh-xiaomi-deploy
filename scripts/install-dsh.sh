#!/bin/sh
# Install DeepSeek Harness on Minis / Alpine ARM64.
# No API key and no Shizuku are required.
set -eu

BASE="${DSH_MINIS_DIR:-/var/minis/shared/deepseek-harness}"
RUNTIME="$BASE/runtime"
BUILD="$BASE/build-node-pty"
VERSION="${DSH_VERSION:-0.1.0-rc.8}"

for cmd in node npm cc c++ make python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    echo "In Minis' Alpine shell, install prerequisites with:" >&2
    echo "  apk add --no-cache build-base python3" >&2
    exit 1
  fi
done

major="$(node -p "Number(process.versions.node.split('.')[0])")"
if [ "$major" -lt 22 ]; then
  echo "Node.js 22+ is required; found $(node --version)." >&2
  exit 1
fi

mkdir -p "$RUNTIME" "$BASE/state"
if [ ! -d "$RUNTIME/node_modules/@deepseek-ai/dsh" ]; then
  printf '{"name":"dsh-minis-runtime","private":true}\n' > "$RUNTIME/package.json"
  (cd "$RUNTIME" && npm install --omit=dev --no-audit --no-fund "@deepseek-ai/dsh@$VERSION")
fi

PTY_DIR="$RUNTIME/node_modules/node-pty"
if [ ! -f "$PTY_DIR/package.json" ]; then
  echo "node-pty was not installed below $RUNTIME/node_modules." >&2
  exit 1
fi
PTY_VERSION="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).version)" "$PTY_DIR/package.json")"

echo "Building node-pty@$PTY_VERSION for Alpine ARM64 (LTO disabled)…"
rm -rf "$BUILD"
mkdir -p "$BUILD"
(cd "$BUILD" && npm pack "node-pty@$PTY_VERSION" --silent >/dev/null)
tar -xzf "$BUILD/node-pty-$PTY_VERSION.tgz" -C "$BUILD"
cd "$BUILD/package"
# Do not run node-pty's automatic installer: it enables LTO under this Node build.
npm install --ignore-scripts --omit=dev --no-audit --no-fund >/dev/null
npm install --ignore-scripts --no-save --no-audit --no-fund node-gyp@12 >/dev/null
npm_config_enable_lto=false ./node_modules/.bin/node-gyp rebuild

mkdir -p "$PTY_DIR/prebuilds/linux-arm64"
cat build/Release/pty.node > "$PTY_DIR/prebuilds/linux-arm64/pty.node"
chmod 755 "$PTY_DIR/prebuilds/linux-arm64/pty.node"

cd "$RUNTIME"
node -e "const p=require('node-pty'); const t=p.spawn('sh',['-c','exit 0'],{name:'xterm'}); t.onExit(()=>process.exit(0)); setTimeout(()=>process.exit(1),2000)"
printf '\nInstalled successfully. Start it with:\n  %s/start-dsh-web.sh\n' "$BASE"
