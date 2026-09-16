#!/usr/bin/env bash
# 把 aw-custom 装到本机的 ActivityWatch 上。可重复运行。
#
#   ./install.sh                # 挂载 + 生成 clean 页 + 换上精简 views + 落地页
#   ./install.sh --no-views     # 不动你现有的 views 布局
#   ./install.sh --redirect     # 额外：让官方界面 / 自动跳到 /pages/clean/（会改 app 文件）
#
# 装之前会先把当前 settings 和 aw-server.toml 备份到 backup/，uninstall.sh 可还原。
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(pwd -P)"
AW=${AW_URL:-http://127.0.0.1:5600}
DO_VIEWS=1; DO_REDIRECT=0
for a in "$@"; do
  case "$a" in
    --no-views) DO_VIEWS=0 ;;
    --redirect) DO_REDIRECT=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "未知参数: $a" >&2; exit 2 ;;
  esac
done

say() { printf '  %s\n' "$*"; }

# ---------- 1. 找 aw-server 的配置目录 ----------
# 测试 / 非标准安装位置可以用 AW_CONFIG_DIR 覆盖
if [ -n "${AW_CONFIG_DIR:-}" ]; then CFG="$AW_CONFIG_DIR"; else
case "$(uname -s)" in
  Darwin) CFG="$HOME/Library/Application Support/activitywatch/aw-server" ;;
  Linux)  CFG="${XDG_CONFIG_HOME:-$HOME/.config}/activitywatch/aw-server" ;;
  MINGW*|MSYS*|CYGWIN*) CFG="$LOCALAPPDATA/activitywatch/aw-server" ;;
  *) echo "认不出这个系统，请手动配置 custom_static" >&2; exit 1 ;;
esac
fi
TOML="$CFG/aw-server.toml"
[ -d "$CFG" ] || { echo "找不到 aw-server 配置目录：$CFG（ActivityWatch 装了并跑过一次吗？）" >&2; exit 1; }
echo "配置目录: $CFG"

# ---------- 2. 备份 ----------
mkdir -p backup
TS=$(date +%Y%m%d-%H%M%S)
[ -f "$TOML" ] && [ ! -f backup/aw-server.toml.bak ] && cp "$TOML" backup/aw-server.toml.bak
if curl -fsS "$AW/api/0/settings" -o "backup/settings-$TS.json" 2>/dev/null; then
  say "settings 已备份到 backup/settings-$TS.json"
  # uninstall 要知道该还原哪一份（装之前的那份）
  [ -f .install-state ] || echo "backup/settings-$TS.json" > .install-state
else
  echo "aw-server 没在跑（$AW）。先启动 ActivityWatch 再来。" >&2; exit 1
fi

# ---------- 3. 写 custom_static ----------
python3 - "$TOML" "$REPO" <<'PY'
import pathlib, re, sys
toml, repo = pathlib.Path(sys.argv[1]), sys.argv[2]
s = toml.read_text() if toml.exists() else ""
mounts = {"clean": repo + "/clean", "rollup": repo + "/rollup", "dayline": repo + "/dayline"}
lines = s.splitlines(True)
if "[server.custom_static]" not in s:
    # 插在 [server] 这一节后面，而不是文件末尾 —— 末尾会落到 [server-testing] 之后，
    # TOML 语义上没错（表名是绝对路径）但读起来像是 testing 的子表
    at = len(lines)
    for i, ln in enumerate(lines):
        if ln.strip() == "[server]":
            at = next((j for j in range(i + 1, len(lines))
                       if lines[j].strip().startswith("[")), len(lines))
            break
    lines[at:at] = ["[server.custom_static]\n"]
out, seen, inside = [], set(), False
for ln in lines:
    if ln.strip().startswith("["):
        if inside:                                  # 离开这一节前补上缺的
            for k, v in mounts.items():
                if k not in seen:
                    out.append(f'{k} = "{v}"\n')
            out.append("\n")
        inside = ln.strip() == "[server.custom_static]"
        out.append(ln); continue
    m = re.match(r'\s*(\w+)\s*=', ln)
    if inside and m and m.group(1) in mounts:
        k = m.group(1); seen.add(k)
        out.append(f'{k} = "{mounts[k]}"\n'); continue
    out.append(ln)
if inside:
    for k, v in mounts.items():
        if k not in seen:
            out.append(f'{k} = "{v}"\n')
toml.write_text("".join(out))
print("  custom_static ->", repo)
PY

# ---------- 4. 重启 aw-server，让挂载生效 ----------
echo "重启 ActivityWatch…"
if [ "$(uname -s)" = "Darwin" ] && [ -d /Applications/ActivityWatch.app ]; then
  osascript -e 'quit app "ActivityWatch"' 2>/dev/null || true
  sleep 3; open -a ActivityWatch
else
  say "自己重启一下 aw-server（挂载只在启动时读一次），然后按回车继续"
  read -r _
fi
for _ in $(seq 1 40); do curl -fsS "$AW/api/0/info" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "$AW/api/0/info" >/dev/null || { echo "aw-server 没起来" >&2; exit 1; }

# ---------- 5. 生成 clean 页 ----------
./clean/build.sh

# ---------- 6. views + 落地页 ----------
if [ "$DO_VIEWS" = 1 ]; then
  curl -fsS -X POST "$AW/api/0/settings/views" -H 'Content-Type: application/json' \
       -d @views-lean.json >/dev/null
  say "已换上精简 views（Overview / Web）。想保留原布局下次加 --no-views，还原用 ./uninstall.sh"
fi
HOSTNAME_AW=$(curl -fsS "$AW/api/0/info" | python3 -c 'import json,sys;print(json.load(sys.stdin)["hostname"])')
curl -fsS -X POST "$AW/api/0/settings/landingpage" -H 'Content-Type: application/json' \
     -d "\"/activity/$HOSTNAME_AW/view/\"" >/dev/null
say "落地页 -> /activity/$HOSTNAME_AW/view/"

# ---------- 7. 可选：老界面自动跳转 ----------
if [ "$DO_REDIRECT" = 1 ]; then
  ./redirect-patch.sh apply || say "跳转补丁没打上（找不到官方 index.html），跳过"
fi

cat <<TXT

装好了。打开: $AW/pages/clean/
  官方界面还在 $AW/ ，随时对照
  卸载: ./uninstall.sh
TXT
