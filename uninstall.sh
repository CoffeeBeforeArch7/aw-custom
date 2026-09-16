#!/usr/bin/env bash
# 把 aw-custom 从本机撤干净，还原成装之前的样子。
set -euo pipefail
cd "$(dirname "$0")"
AW=${AW_URL:-http://127.0.0.1:5600}

# 测试 / 非标准安装位置可以用 AW_CONFIG_DIR 覆盖
if [ -n "${AW_CONFIG_DIR:-}" ]; then CFG="$AW_CONFIG_DIR"; else
case "$(uname -s)" in
  Darwin) CFG="$HOME/Library/Application Support/activitywatch/aw-server" ;;
  Linux)  CFG="${XDG_CONFIG_HOME:-$HOME/.config}/activitywatch/aw-server" ;;
  MINGW*|MSYS*|CYGWIN*) CFG="$LOCALAPPDATA/activitywatch/aw-server" ;;
  *) echo "认不出这个系统" >&2; exit 1 ;;
esac
fi

# 1. 老界面的跳转补丁
./redirect-patch.sh revert 2>/dev/null || echo "  跳转补丁：没打过或找不到目标，跳过"

# 2. settings（views / landingpage）还原成装之前那份
SNAP=$( [ -f .install-state ] && cat .install-state || ls -1t backup/settings-*.json 2>/dev/null | tail -1 )
if [ -n "${SNAP:-}" ] && [ -f "$SNAP" ]; then
  python3 - "$SNAP" "$AW" <<'PY'
import json, sys, urllib.request
snap, aw = json.load(open(sys.argv[1])), sys.argv[2]
for key in ("views", "landingpage"):
    if key not in snap: continue
    req = urllib.request.Request(f"{aw}/api/0/settings/{key}",
        data=json.dumps(snap[key]).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    urllib.request.urlopen(req, timeout=10).read()
    print(f"  已还原 {key}")
PY
else
  echo "  没找到装之前的 settings 快照，views/landingpage 请自己在界面上改回去"
fi

# 3. custom_static 挂载
if [ -f backup/aw-server.toml.bak ]; then
  cp backup/aw-server.toml.bak "$CFG/aw-server.toml"; echo "  aw-server.toml 已还原"
else
  python3 - "$CFG/aw-server.toml" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
if p.exists():
    keep = [l for l in p.read_text().splitlines(True)
            if not re.match(r'\s*(clean|rollup|dayline)\s*=', l)]
    p.write_text("".join(keep)); print("  已摘掉 clean/rollup/dayline 挂载")
PY
fi

echo
echo "重启 ActivityWatch 生效。仓库目录本身没动，删掉即可。"
