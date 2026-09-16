import json, re, sys, urllib.request, urllib.parse, datetime, collections

API = "http://127.0.0.1:5600/api/0"
def get(p): return json.load(urllib.request.urlopen(API + p))
HOST = get("/info")["hostname"]   # 别写死主机名，换机器就废了
def evs(bucket, s, e):
    q = urllib.parse.quote
    return get(f"/buckets/{bucket}/events?limit=-1&start={q(s)}&end={q(e)}")

def iv(e):
    s = datetime.datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00"))
    return s, s + datetime.timedelta(seconds=e["duration"])

def merge(ivs):
    out = []
    for s, e in sorted(ivs):
        if out and s <= out[-1][1]: out[-1][1] = max(out[-1][1], e)
        else: out.append([s, e])
    return out

def clip(s, e, spans):  # 返回 [s,e] 落在 spans 里的秒数
    t = 0.0
    for a, b in spans:
        if b <= s: continue
        if a >= e: break
        t += (min(e, b) - max(s, a)).total_seconds()
    return t

classes = get("/settings/classes")
rules = [(c["name"], re.compile(c["rule"]["regex"], re.I if c["rule"].get("ignore_case") else 0))
         for c in classes if c["rule"].get("type") == "regex"]

def cat(data):  # aw-core：正则对 data 的每个字符串字段单独匹配，取最深的命中
    hits = [n for n, rx in rules if any(isinstance(v, str) and rx.search(v) for v in data.values())]
    return max(hits, key=len) if hits else None

days = int(sys.argv[1]) if len(sys.argv) > 1 else 0
tz = datetime.datetime.now().astimezone().tzinfo
now = datetime.datetime.now(tz)
end_ = now
start = now.replace(hour=4, minute=0, second=0, microsecond=0) - datetime.timedelta(days=days)

afk = evs(f"aw-watcher-afk_{HOST}", start.isoformat(), end_.isoformat())
active = merge([iv(e) for e in afk if e["data"]["status"] == "not-afk"])

win = evs(f"aw-watcher-window_{HOST}", start.isoformat(), end_.isoformat())
web = evs(f"aw-watcher-web-chrome_{HOST}", start.isoformat(), end_.isoformat())
isbrowser = re.compile(r"chrome|safari|firefox|edge|^arc$", re.I)
chrome_spans = merge([iv(e) for e in win if isbrowser.search(e["data"].get("app", ""))])

uncat = collections.Counter(); allcat = collections.Counter()
for e in win:
    app = e["data"].get("app", "?")
    if isbrowser.search(app): continue          # 浏览器时间由 web bucket 细分
    s, t = iv(e); d = clip(s, t, active)
    if d <= 0: continue
    c = cat(e["data"])
    allcat[" > ".join(c) if c else "Uncategorized"] += d
    if not c: uncat[(app, e["data"].get("title", "")[:60])] += d
for e in web:
    s, t = iv(e); d = clip(s, t, active)
    if d > 0: d = min(d, clip(s, t, chrome_spans))
    if d <= 0: continue
    c = cat(e["data"])
    host = urllib.parse.urlparse(e["data"].get("url", "")).netloc or e["data"].get("url", "")[:30]
    allcat[" > ".join(c) if c else "Uncategorized"] += d
    if not c: uncat[("[web] " + host, e["data"].get("title", "")[:60])] += d

def hm(s):
    s = int(s); return f"{s//3600}h{s%3600//60:02d}m" if s >= 3600 else f"{s//60}m{s%60:02d}s"

print(f"窗口 {start:%m-%d %H:%M} → {end_:%m-%d %H:%M}（已过滤 AFK）")
print(f"未分类 {hm(sum(uncat.values()))} / 总计 {hm(sum(allcat.values()))}\n")
byapp = collections.Counter()
for (a, t), v in uncat.items(): byapp[a] += v
print("未分类 — 按 app / 域名:")
for k, v in byapp.most_common(20): print(f"  {hm(v):>8}  {k}")
print("\n未分类 — 明细:")
for (a, t), v in uncat.most_common(25): print(f"  {hm(v):>8}  {a:24} | {t}")
