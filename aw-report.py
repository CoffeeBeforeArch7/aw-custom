#!/usr/bin/env python3
"""aw-report.py — ActivityWatch 时间体检报告（给 /check 用）

一条 query 拉整段区间的已分类事件，本地按「学习日」（startOfDay，默认 04:00）切片。
口径和 Overview 页一致：flood + 排除 AFK + 用 Settings 里的分类规则 categorize。

usage:
  python3 aw-report.py            # 最近 8 天
  python3 aw-report.py --days 14
  python3 aw-report.py --json     # 机器可读，喂给别的工具
"""

import argparse
import collections
import datetime
import json
import sys
import urllib.request

API = "http://127.0.0.1:5600/api/0"
BLOCK_GAP = 180   # 中断 ≤ 3min 仍算同一块

# 想在表里单独占一列的分类，写完整路径（最多 3 个）。
# 留 [] 就只显示自动分组的「产出 / 干扰」两列。
# 「产出 / 干扰 / 专注块」本身不写死分类名 —— 按 Settings → Categorization 里设的
# score 判定：顶级分类 score > 0 算产出，< 0 算干扰。换一套分类体系不用改代码。
WATCH = ["Study", "Study > English", "Career"]


def api(path, body=None):
    req = urllib.request.Request(
        API + path,
        data=json.dumps(body).encode() if body else None,
        headers={"Content-Type": "application/json"} if body else {},
    )
    return json.load(urllib.request.urlopen(req, timeout=120))


def hm(sec):
    sec = int(sec)
    return f"{sec // 3600}:{sec % 3600 // 60:02d}"


def build_query(host, classes):
    # query2 的字符串字面量吃一层反斜杠，必须先还原，否则 \d \. 这类规则全失配
    rules = json.dumps(
        [[c["name"], c["rule"]] for c in classes if c["rule"].get("type") == "regex"]
    ).replace("\\\\", "\\")
    return "\n".join([
        f'events = flood(query_bucket(find_bucket("aw-watcher-window_{host}")));',
        f'not_afk = flood(query_bucket(find_bucket("aw-watcher-afk_{host}")));',
        'not_afk = filter_keyvals(not_afk, "status", ["not-afk"]);',
        'events = filter_period_intersect(events, not_afk);',
        f'events = categorize(events, {rules});',
        'RETURN = sort_by_timestamp(events);',
    ])


def top_scores(classes):
    """顶级分类 -> score。没设的算 0。"""
    return {c["name"][0]: (c.get("data") or {}).get("score") or 0
            for c in classes if len(c["name"]) == 1}


def score_of(classes):
    table = {}
    for c in classes:
        table[tuple(c["name"])] = (c.get("data") or {}).get("score")

    def get(path):
        p = tuple(path)
        while p:
            if table.get(p) is not None:
                return table[p]
            p = p[:-1]
        return 0
    return get


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=8)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    info = api("/info")
    host = info["hostname"]
    settings = api("/settings")
    classes = settings.get("classes", [])
    day_start_h, day_start_m = (int(x) for x in (settings.get("startOfDay") or "04:00").split(":"))
    getscore = score_of(classes)
    tops = top_scores(classes)
    if not any(tops.values()):
        sys.exit("还没给顶级分类设 score（Settings → Categorization），"
                 "「产出 / 干扰 / 专注块」无从判定。先设完再跑。")
    prod_tops = {k for k, v in tops.items() if v > 0}
    distr_tops = {k for k, v in tops.items() if v < 0}

    tz = datetime.datetime.now().astimezone().tzinfo
    now = datetime.datetime.now(tz)
    # 00:00–04:00 之间跑的时候，「今天」其实还是昨天那个学习日 —— 从学习日往回数，
    # 不然 --days 8 只会出 7 行
    last_day = (now - datetime.timedelta(hours=day_start_h, minutes=day_start_m)).date()
    first = datetime.datetime.combine(
        last_day - datetime.timedelta(days=args.days - 1),
        datetime.time(day_start_h, day_start_m), tzinfo=tz)

    events = api("/query/", {
        "timeperiods": [f"{first.isoformat()}/{now.isoformat()}"],
        "query": [build_query(host, classes)],
    })[0]

    def study_day(ts):
        t = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone(tz)
        t -= datetime.timedelta(hours=day_start_h, minutes=day_start_m)
        return t.date()

    days = collections.OrderedDict()
    d = first.date()
    while d <= study_day(now.isoformat()):
        days[d] = {"cats": collections.Counter(), "apps": collections.Counter(),
                   "score": 0.0, "focus": [], "active": 0.0}
        d += datetime.timedelta(days=1)

    for e in events:
        day = study_day(e["timestamp"])
        if day not in days:
            continue
        bucket = days[day]
        path = e["data"].get("$category") or ["Uncategorized"]
        dur = e["duration"]
        bucket["cats"][" > ".join(path)] += dur
        bucket["apps"][e["data"].get("app") or "?"] += dur
        bucket["active"] += dur
        bucket["score"] += dur / 3600 * (getscore(path) or 0)
        if path[0] in prod_tops:
            start = datetime.datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00"))
            bucket["focus"].append((start, start + datetime.timedelta(seconds=dur)))

    def longest_block(spans):
        if not spans:
            return 0
        spans.sort()
        best = cur = (spans[0][1] - spans[0][0]).total_seconds()
        end = spans[0][1]
        for s, e_ in spans[1:]:
            if (s - end).total_seconds() <= BLOCK_GAP:
                cur += (e_ - max(s, end)).total_seconds()
            else:
                cur = (e_ - s).total_seconds()
            end = max(end, e_)
            best = max(best, cur)
        return best

    def watch_dur(cats, path):
        """完整路径：自己 + 所有子分类。"""
        return sum(d for name, d in cats.items() if name == path or name.startswith(path + " > "))

    rows = []
    for day, b in days.items():
        top = collections.Counter()
        for name, dur in b["cats"].items():
            top[name.split(" > ")[0]] += dur
        rows.append({
            "date": day.isoformat(),
            "active": b["active"],
            "watch": [watch_dur(b["cats"], w) for w in WATCH],
            "prod": sum(top[t] for t in prod_tops),
            "distraction": sum(top[t] for t in distr_tops),
            "uncategorized": b["cats"].get("Uncategorized", 0),
            "score": round(b["score"], 1),
            "longest_focus": longest_block(b["focus"]),
            "top_cats": b["cats"].most_common(6),
            "top_apps": b["apps"].most_common(6),
        })

    if args.json:
        print(json.dumps({"host": host, "watch": WATCH, "days": rows}, ensure_ascii=False, indent=2))
        return

    print(f"AW 报告  {rows[0]['date']} → {rows[-1]['date']}  ({len(rows)} 天, 日界 "
          f"{day_start_h:02d}:{day_start_m:02d})\n")
    labels = [w.split(" > ")[-1][:7] for w in WATCH]
    head = (f"{'date':<7}{'active':>7}" + "".join(f"{l:>8}" for l in labels)
            + f"{'prod':>7}{'distr':>7}{'score':>8}{'block':>8}")
    print(head)
    print("-" * len(head))

    def line(label, get):
        cells = "".join(f"{hm(get('watch', i)):>8}" for i in range(len(WATCH)))
        return (f"{label:<7}{hm(get('active')):>7}{cells}{hm(get('prod')):>7}"
                f"{hm(get('distraction')):>7}{get('score'):>8.1f}{hm(get('longest_focus')):>8}")

    for r in rows:
        print(line(r["date"][5:], lambda k, i=None, r=r: r[k][i] if i is not None else r[k]))
    n = len(rows)

    def avg(k, i=None):
        return sum((r[k][i] if i is not None else r[k]) for r in rows) / n

    print(line("avg", avg))

    t = rows[-1]
    print(f"\n今天 {t['date']}")
    print("  分类: " + " | ".join(f"{k} {hm(v)}" for k, v in t["top_cats"][:5]))
    print("  应用: " + " | ".join(f"{k} {hm(v)}" for k, v in t["top_apps"][:5]))
    print(f"  未分类: {hm(t['uncategorized'])}" + ("   ← 该补规则了" if t["uncategorized"] > 600 else "   ok"))

    if n >= 6:
        recent, before = rows[-3:], rows[:-3]
        print(f"\n最近 3 天 vs 前 {len(before)} 天（日均）")
        series = [(w.split(" > ")[-1], i) for i, w in enumerate(WATCH)]
        series += [("产出", None), ("干扰", None)]
        for label, i in series:
            key = "watch" if i is not None else ("prod" if label == "产出" else "distraction")
            pick = lambda r, i=i, key=key: r[key][i] if i is not None else r[key]
            a = sum(pick(r) for r in recent) / len(recent)
            b = sum(pick(r) for r in before) / len(before)
            delta = a - b
            sign = "+" if delta >= 0 else "-"
            print(f"  {label:<12}{hm(a):>7}  ({sign}{hm(abs(delta))})")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.URLError as e:
        sys.exit(f"连不上 aw-server ({API}): {e}")
