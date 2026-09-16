#!/usr/bin/env bash
# 往官方 index.html 里插一行 script，让 http://127.0.0.1:5600/ 自动跳到 /pages/clean/。
#
#   ./redirect-patch.sh apply
#   ./redirect-patch.sh revert
#
# 这是唯一会改 ActivityWatch 自身文件的操作，其余功能都只用官方的扩展点。
# 注意：AW 升级会覆盖掉它，升级后重跑一次。macOS 上这会让 app 的代码签名失效
# （实测照常启动；万一起不来，先 revert，再 codesign --force --deep --sign - /Applications/ActivityWatch.app）。
set -euo pipefail
# Windows 上 "$PYBIN" 通常叫 python
PYBIN=$(command -v python3 || command -v python) || { echo "需要 python 3" >&2; exit 1; }
cd "$(dirname "$0")"
LINE='<script src="/pages/clean/redirect.js"></script>'

find_index() {
  [ -n "${AW_STATIC:-}" ] && { echo "$AW_STATIC"; return; }
  local c
  local win=""
  command -v cygpath >/dev/null 2>&1 && win=$(cygpath -u "${LOCALAPPDATA:-}" 2>/dev/null || true)
  for c in \
    "/Applications/ActivityWatch.app/Contents/Resources/aw_server/static/index.html" \
    "$HOME/Applications/ActivityWatch.app/Contents/Resources/aw_server/static/index.html" \
    "${win:+$win/Programs/ActivityWatch/aw_server/static/index.html}" \
    "/c/Program Files/ActivityWatch/aw_server/static/index.html" \
    "/c/Program Files (x86)/ActivityWatch/aw_server/static/index.html"
  do [ -n "$c" ] && [ -f "$c" ] && { echo "$c"; return; }; done
  # pip / 包管理器装的
  c=$("$PYBIN" - <<'PY' 2>/dev/null || true
import pathlib
try:
    import aw_server
    p = pathlib.Path(aw_server.__file__).parent / "static" / "index.html"
    print(p if p.exists() else "")
except Exception:
    print("")
PY
)
  [ -n "$c" ] && { echo "$c"; return; }
  return 1
}

DST=$(find_index) || { echo "找不到官方 index.html。用 AW_STATIC=/path/to/static/index.html 指给我。" >&2; exit 1; }
echo "目标: $DST"
mkdir -p backup

case "${1:-}" in
  apply)
    [ -f backup/official-index.html.orig ] || cp "$DST" backup/official-index.html.orig
    if grep -q "pages/clean/redirect.js" "$DST"; then echo "已经打过了"; exit 0; fi
    "$PYBIN" - "$DST" "$LINE" <<'PY'
import pathlib, sys
p, line = pathlib.Path(sys.argv[1]), sys.argv[2]
s = p.read_text()
assert "</head>" in s, "不像 index.html"
# 必须是外链 script：官方页的 CSP 是 script-src 'self'，不含 'unsafe-inline'
p.write_text(s.replace("</head>", line + "</head>", 1))
PY
    echo "打上了。/ 和 /index.html 现在会跳到 /pages/clean/"
    ;;
  revert)
    if [ -f backup/official-index.html.orig ]; then
      cp backup/official-index.html.orig "$DST"; echo "已从备份还原"
    else
      "$PYBIN" - "$DST" "$LINE" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace(sys.argv[2], ""))
PY
      echo "已移除那行 script"
    fi
    ;;
  *) sed -n '2,6p' "$0"; exit 2 ;;
esac
