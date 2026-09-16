#!/usr/bin/env bash
# 把 aw-server 的 settings（views + 分类规则 + landingpage）导出到 backup/。
# 这些东西只存在 peewee-sqlite.v2.db 里，改完分类规则记得跑一次。
set -e
# Windows 上 "$PYBIN" 通常叫 python
PYBIN=$(command -v python3 || command -v python) || { echo "需要 python 3" >&2; exit 1; }
cd "$(dirname "$0")"
OUT="backup/settings-$(date +%Y%m%d-%H%M%S).json"
curl -sf http://127.0.0.1:5600/api/0/settings | "$PYBIN" -m json.tool > "$OUT"
"$PYBIN" -c "
import json,sys
d=json.load(open('$OUT'))
print('$OUT', '->', len(d.get('classes',[])), '条分类,', len(d.get('views',[])), '个 view')
"
# 只留最近 10 份
ls -1t backup/settings-*.json | tail -n +11 | xargs -r rm -f
