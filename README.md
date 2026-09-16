# aw-custom

给 [ActivityWatch](https://activitywatch.net/) 换一套精简界面，外加三个自定义可视化。
不改官方代码，装/卸都是一条命令。

> A drop-in overlay for ActivityWatch: a stripped-down UI plus three custom
> visualizations (a per-day stacked timeline, a category donut, and a CLI report).
> It ships no ActivityWatch source — everything hangs off the official
> `custom_static` / `custom_vis` / settings-API extension points.
> Docs below are in Chinese.

## 它是什么 / 不是什么

**不是 fork。** 仓库里没有一行 ActivityWatch 的源码。它用的全是官方自己开的口子：

| 用到的官方扩展点 | 做什么 |
|---|---|
| `aw-server.toml` 的 `[server.custom_static]` | 把 `clean/` `rollup/` `dayline/` 挂到 `/pages/*` |
| 官方 vis 类型 `custom_vis` | 用 iframe 加载自定义图，并把 `hostname/start/end/title` 传进来 |
| `/api/0/settings` | views 布局、分类规则、落地页 |
| `/api/0/query/` | 和官方 Overview 完全同一条 canonical query |

浏览器 watcher 是**动态认**的：chrome / firefox / edge / brave / vivaldi / arc / opera / yandex / orion
都能识别（app 名单抄自 aw-webui 的 `browser_appnames`），所以 Windows 上用 Edge 也和官方 Overview 口径一致。

`clean/index.html` 是**复制**官方 `index.html`、加载同一份官方 Vue bundle（绝对路径 `/js/*`，同源），
只额外注入自己的 CSS/JS。所以官方界面原样保留在 `/`，随时对照。

唯一会改到 ActivityWatch 自身文件的是可选的跳转补丁（`./redirect-patch.sh`），单独一条命令，可撤。

代价要说清楚：它依赖了一些**官方的私有实现**（`isVisLarge` 写死、views 的 `size` 字段没被读、
query2 吃反斜杠），这些不是公开契约，官方改了就会碎。见文末「踩过的坑」。

## 装

需要：ActivityWatch 已安装并至少跑过一次、Python 3、`curl`、一个 bash。
浏览器需要 Chrome 105+ / Firefox 121+ / Safari 15.4+（用到了 CSS `:has()` 和 `ResizeObserver`）。

| 平台 | 怎么跑 |
|---|---|
| macOS | 直接 `./install.sh`，会自动重启 ActivityWatch |
| Linux | `./install.sh`，脚本会让你手动重启 aw-server 后按回车 |
| Windows | 用 **Git Bash** 跑 `bash install.sh`（不是 PowerShell）。同样会让你手动重启 |

Windows 上还有两处会自动处理：`python3` 一般叫 `python`，脚本自己探测；
Git Bash 的 `/c/Users/…` 路径会用 `cygpath -m` 转成 `C:/Users/…` 再写进 TOML
（aw-server 是原生进程，而且 `C:\Users` 里的 `\U` 在 TOML basic string 里是非法转义）。

```sh
git clone <this repo> aw-custom && cd aw-custom
./install.sh
```

干了这些事（都会先备份到 `backup/`）：

1. 把仓库路径写进 `aw-server.toml` 的 `custom_static`（macOS / Linux / Windows 路径自动判断）
2. 重启 aw-server（挂载只在启动时读一次）
3. 从**正在运行的 server** 抓官方 `index.html`，生成 `clean/index.html`
4. 换上精简 views（Overview / Web），落地页指到 Overview

装完打开 <http://127.0.0.1:5600/pages/clean/>。

```sh
./install.sh --no-views    # 保留你现有的 views 布局
./install.sh --redirect    # 额外让官方界面 / 自动跳到 /pages/clean/（会改 app 文件）
./uninstall.sh             # 全部还原（含 views、落地页、挂载、跳转补丁）
```

**想让「产出 / 摸鱼」这些判定生效**，得在 Settings → Categorization 里给顶级分类填 score
（正数 = 产出，负数 = 干扰）。代码里不写死任何分类名，全按 score 推导，所以你的分类体系怎么定都行。
没填 score 的话图照画，只是诊断那几行会提示你去填。

## 组成

### `clean/` — 精简外壳

入口 `/pages/clean/`。同一份官方 bundle + 自己的 CSS/JS，路由是 hash 模式所以照常工作。

砍掉：Host 行、`+ New view`、`Edit view`、页脚、uncategorized/更新/问卷横幅、时间轴下面那行说明。
加上：图表卡片化、tab 条极简、时间轴左侧 bucket 名缩短（`aw-watcher-web-chrome_<host>` → `Website`）、
Score 卡条目悬停联动右边环图。

想要回某个东西：改 `clean/clean.js` 顶部 `CFG` 里对应项为 `true`，刷新。

### `dayline/` — 时间带（一天怎么过的）

替掉官方 `vis_timeline`。官方那个按 bucket 分行、按 app 着色、只能看单天，答得了「在用什么」，
答不了「这段是在学习还是在摸鱼」。dayline 反过来：**按分类着色、按天堆成网格**。

- 一行 = 一个学习日（`startOfDay`，默认 04:00 起算 24h），最近 7 / 14 / 30 天
- 一格 = 5 / 15 / 30min（默认 15min）
- **每格是一根堆叠柱**，自底向上按 score 从高到低排，所以**贴底那条颜色的厚度 = 产出强度随时间的变化**
- 每段高度 = 该分类在这格的占比；**整根柱子的总高 = 在机占比**，顶上空着的就是不在电脑前
- 配色两档：**重点**（score ≠ 0 的分类保留原色，中性的并成一段灰）/ **全部分类**
- period=day 时画「这天 + 往前 N-1 天」，period=week/month 时铺满整个区间
- 悬停看那一格的**完整构成**；点左边日期跳到那天的 Overview
- 行高跟天数走：7 天 28px / 14 天 20px / 30 天 14px

三种「没干活」是分开画的，混在一起这图就废了：

| 画法 | 含义 |
|---|---|
| 柱子顶上留白 | 没开机 / 不在电脑前 |
| 底部一条细线 | 连续 20min+ 没输入 —— 机器开着但人不在（`AWAY_SEC`） |
| 柱子顶上一段最浅的灰 | 在桌前但没输入（短暂走神） |
| 彩色段 | 真在用，颜色 = 分类 |

AFK watcher 只报 `afk` / `not-afk`，不区分「泡杯咖啡」和「睡觉时机器没关」。
实测一天 `away` 能有 11h，全涂成灰的话整夜都是灰的，图就没信息量了 —— 所以按单个 afk 事件的时长切两档。
跨日界的 afk 事件会被 04:00 的查询窗切断，尾巴那截贴着窗口边缘的一律按截断处理，否则会被误画成「发呆」。

图下面还有几行诊断（示例数字）：

```
最近 7 天 · 日均活跃 10h49m · 产出 6h28m（60%）· 摸鱼 1h28m
最稳 15:00–18:00 · 日均产出 1h44m / 3h
起步 中位 11:35 才开始出活（最早 09:00 · 最晚 12:50，7/7 天有产出）
```

- **最稳 / 最空**：3h 滑窗里日均产出最高 / 最低的一段。「醒着」只认 active + 短 afk，长 afk 不算 ——
  早期版本把整夜开机算成「有记录」，于是一本正经地报「最空 04:00–07:00」，那是睡觉不是浪费。
- **最空只在「人已经在机器前」时才报**（该时段日均在机 ≥ 30min）。不满足就不显示。
- **起步** = 每天第一次「站住脚」的时刻：往后 30min 内至少攒够 15min 产出。
  不加这个窗口条件的话，凌晨一个 5min 的闪现就能把起步时间拉到 05:00。

### `rollup/` — Time by Category 环图

替掉官方的 `top_categories` + `category_sunburst`，两者合一：小于阈值的分类并成 `Others`，
内圈分类、外圈明细，点扇区下钻、点中心返回，Score 卡悬停联动高亮。

### `aw-report.py` — 命令行体检表

```sh
python3 aw-report.py            # 最近 8 天
python3 aw-report.py --days 14
python3 aw-report.py --json     # 机器可读
```

输出 N 天表（在机 / 关注的分类 / 产出 / 干扰 / score / 最长专注块）+ 今天的分类和应用 Top5
+ 未分类时长 + 最近 3 天 vs 之前的日均差。

- 顶部 `WATCH` 常量：想单独占一列的分类，写完整路径；留 `[]` 就只显示自动分组的产出/干扰
- **一条 query 拉整段区间**再本地按 startOfDay 切天 —— 按天分别发 query 会慢一个数量级
- 口径和 `/pages/clean/` 的 Overview 完全一致

### `uncategorized.py` — 分类维护

列出「被记录到、但没命中任何分类规则」的时间，按 app / 域名 + 窗口标题排序，已过滤 AFK
并把浏览器时间下钻到域名。

```sh
python3 uncategorized.py      # 今天
python3 uncategorized.py 7    # 最近 7 天
```

拿到列表 → Settings → Categorization 加规则 → 再跑一次确认归零。**建议每周跑一次**。

规则写法要点（aw-core 语义，实测确认）：

- 正则是**对 event data 的每个字段单独 search**（app / title / url 分开匹配），
  所以 `^Code$` 能精确命中 app 名 `Code` 而不误伤 `Claude Code`
- 多条规则同时命中时**层级更深的赢**（`Study > Code` 打败 `Study`），同深度按分类列表顺序
- `ignore_case` 默认开
- 给「不算活动」的东西单独建中性分类（登录窗口、新标签页、搜索页、系统弹窗），score 设 0，
  否则它们会稀释你的产出占比

### `backup-settings.sh`

把 views + 分类规则 + 落地页导出到 `backup/`。**这些东西只存在 aw-server 的 sqlite 里**，
手滑点一下 Settings 里的 "Restore defaults" 就没了，改完规则记得跑一次。

## ActivityWatch 升级之后

官方 bundle 的文件名带哈希，升级后 `clean/index.html` 会失效（页面空白，5 秒后有提示）：

```sh
./clean/build.sh                 # 重新抓
./redirect-patch.sh apply        # 如果用了跳转补丁，也会被覆盖，重打一次
```

## 踩过的坑

按「别人也会踩」排序：

**query2 的字符串字面量吃一层反斜杠。** `categorize(events, <rules>)` 里的规则是写在 query
字符串里的 JSON，直接 `JSON.stringify(rules)` 发过去，`\d` `\.` `\s` 到服务端全变成废的，
**所有带转义的规则静默失配**，Overview 里就是一大片 Uncategorized。aw-webui 自己是
`.replace(/\\\\/g, "\\")` 处理的，自己写查询必须照抄。

**iframe 里不能跟系统深色模式。** `prefers-color-scheme` 在 iframe 里跟的是 OS，
而 ActivityWatch 的深色是运行时插 `dark.css`。系统深色 + AW 浅色时整张图会变成黑条。
改成读父窗口有没有 `dark.css`（同源，可以直接读）。

**`isVisLarge` 在 bundle 里写死**成 `sunburst_clock` / `vis_timeline`，`custom_vis` 配不出整宽；
而且 views JSON 里的 `size` 字段这个版本**根本没被读**。所以整宽只能靠 `clean.js` 认出
iframe src 再由 CSS 撑开 —— 在官方界面（没有 clean.js）下自定义图只有 1/3 宽。

**汇报 iframe 高度时别用 `documentElement.scrollHeight`。** 它有个「不低于视口高」的下限，
而视口高又是上一次汇报的结果 —— 棘轮式越报越高，卡片下面留出一大块空白。只量内容根节点自己。
另外光靠几个 `setTimeout` 补汇报不够：字体加载完、控件换行、图例多一行都会改高度，得挂
`ResizeObserver`，否则窄窗口下 iframe 里会出滚动条。

**首帧量不到真实宽度。** iframe 刚插进去时还是 CSS 默认宽度，这时候算出来的列宽会让时间刻度
停在最粗的档位。量真正承载时间轴的那个元素，并在布局稳定后补测。

## 设计笔记：dayline 为什么是堆叠

第一版是 argmax：一格涂成里面时长最多的那个分类的颜色，高度表示活跃占比。拿真实数据量完就推翻了
（某台机器 7 天、82.3h 活跃时间）：

| | 15min 格 | 30min 格 |
|---|---|---|
| 柱子高度 ≥90%（几乎顶格） | **59%** | 46% |
| 格内有 ≥2 个分类各占 ≥1min | **73%** | 82% |
| **被 argmax 涂错颜色的活跃时间** | **37%（30.1h）** | 41% |

两个结论：**高度那个通道是浪费的**（一多半顶格，信息量接近零，却占着最强的视觉权重）；
**颜色在大面积说谎** —— 真实行为是高频切换，argmax 恰好把这个最该被看见的特征抹平成整齐色块，
**把碎片化的一天画得比实际整齐**。而且调粗格子会更糟（30min 错到 41%），所以「粗一点就清爽了」
是靠撒谎换来的。

但全量堆叠也不行，同样量过：**60% 的格子会出现 <3px 的薄片**（18px 行高下），诚实但读不出来。

最后取的折中：

1. **语义分组**（中性分类并成一段「其它」），薄片含义退化成「这段混了点杂事」——
   有无本身是信号，精确值去 tooltip 读。正确性问题 > 精度问题。
2. **行高加到 28px**（7 天时），薄片阈值从「要占 11% 才有 2px」降到 7%。
3. **按 score 排序、产出贴底**，一行横扫过去就能读出产出强度的变化曲线。
4. 整根柱子设了 `MIN_STACK = 12%` 的最小可见高度（段间比例不变），否则 30min 格里 1min 的活动
   画出来只有 3% 高，等于看不见。

> **改完堆叠之后又发现一个更底层的 bug**：存储层虽然是 5min 格，但**每格仍然只存 argmax 分类**，
> 所以「堆叠 = 零信息丢失」是假的 —— 实测 5min 这一层自己就丢掉 **34.2% 的活跃时间**，
> 比 15min 的 37% 几乎没改善。根因是事件密度太高：**平均每个 5min 格里有 3.46 个不同分类**
> （约 10s 一个事件）。已改成每格存完整明细 `[分类下标, 秒, …]`。
> 影响范围要说准：**聚合数字只错了 4%**（argmax 的误差在多格之间互相抵消），
> 错得厉害的是**画面本身和 tooltip**。修完用逐事件口径端到端校过，日均活跃/产出/摸鱼三项完全一致。

### 性能：为什么是「按天查 + 本地切格」

| 试过的做法 | 实测 |
|---|---|
| 一次拉 7 天原始事件 | 16s / 5.5MB |
| **按天拉（约 4.7k 事件/天）** | **1.7–3.3s / 1MB** ← 用这个 |
| 288 个 5min timeperiod 交给服务端 `merge_events_by_keys` | **63s**，每个 period 固定开销 ~0.2s |

所以：每天单独查 → 本地切成 5min 格 → **切好的格存 localStorage**
（`dayline:<host>:<日期>`，稀疏数组 + 字符串表，约 5KB/天）。过去的天永远不再查，只有今天每次重查。
缓存 key 带分类规则的哈希，改了规则自动失效。显示粒度只是把 5min 格并起来，不重新查。

## 许可

MIT。ActivityWatch 本身是 MPL-2.0，本仓库不含其代码。
