#!/usr/bin/env bash
# 从「正在运行的 aw-server」抓官方 index.html，生成 clean/index.html。
#
# 为什么走 HTTP 而不是读安装目录：官方 bundle 的文件名带哈希，每次升级都变，
# 而安装路径每个平台都不一样（macOS 在 .app 里，Linux 在 site-packages，Windows 在 AppData）。
# 从 server 抓永远对得上当前正在跑的那个版本，且跨平台。
set -euo pipefail
# Windows 上 "$PYBIN" 通常叫 python
PYBIN=$(command -v python3 || command -v python) || { echo "需要 python 3" >&2; exit 1; }
cd "$(dirname "$0")"
AW=${AW_URL:-http://127.0.0.1:5600}

curl -fsS "$AW/index.html" -o .official.html || {
  echo "抓不到 $AW/index.html —— aw-server 没在跑？" >&2; exit 1; }

"$PYBIN" - <<'PY'
import pathlib
src = pathlib.Path(".official.html").read_text()
assert "</head>" in src, "抓回来的不像 index.html"
# 官方页上可能已经被打过跳转补丁，别把它带进 clean 页（会自己跳自己）
src = src.replace('<script src="/pages/clean/redirect.js"></script>', "")
out = src.replace("</head>",
    '<link href="clean.css" rel="stylesheet">'
    '<script defer="defer" src="clean.js"></script></head>', 1)
out = out.replace("<title>ActivityWatch</title>", "<title>ActivityWatch · Clean</title>", 1)
pathlib.Path("index.html").write_text(out)
PY

rm -f .official.html
echo "clean/index.html 已按 $AW 当前的 bundle 重新生成"
