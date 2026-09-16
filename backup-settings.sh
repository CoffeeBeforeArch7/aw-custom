#!/bin/zsh
# 把 aw-server 的 settings（views + 分类规则 + landingpage）导出到 backup/。
# 这些东西只存在 peewee-sqlite.v2.db 里，改完分类规则记得跑一次。
set -e
cd "$(dirname "$0")"
OUT="backup/settings-$(date +%Y%m%d-%H%M%S).json"
curl -sf http://127.0.0.1:5600/api/0/settings | python3 -m json.tool > "$OUT"
python3 -c "
import json,sys
d=json.load(open('$OUT'))
print('$OUT', '->', len(d.get('classes',[])), '条分类,', len(d.get('views',[])), '个 view')
"
# 只留最近 10 份
ls -1t backup/settings-*.json | tail -n +11 | xargs -r rm -f
