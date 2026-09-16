/*
 * aw-custom/clean — 精简版 ActivityWatch UI
 *
 * 不改官方 app bundle，只是在 /pages/clean/ 下用同一份 Vue app + 自己的 CSS/JS。
 * 老界面 http://127.0.0.1:5600/ 原样保留，随时对照。
 *
 * 想要回某个东西：把下面 CFG 里对应项改成 true，刷新页面。
 */
(function () {
  'use strict';

  var CFG = {
    periodBars: true, // 顶部那排 period 柱状图（最近 N 天/周活跃时长，点一下跳到那天）
    hostLine: false, // "Host: <hostname>" 那一行
    filtersBtn: true, // Filters 按钮
    notifications: false, // uncategorized / new release / satisfaction poll 横幅
    newViewTab: false, // tab 条右侧的 "+ New view"
    editViewBtn: false, // 图表下方的 "Edit view"
    footer: false, // 页脚（Made with ♥ / 版本号 / 各种外链）
    timelineHint: false, // 时间轴下面那行 "Buckets with no events..." 说明
    cards: true, // 把每个图表包成卡片
    shortBucketNames: true, // 时间轴左边 aw-watcher-afk_<host> → At Computer
  };

  var BUCKET_LABELS = {
    afk: 'At Computer',
    window: 'App',
    input: 'Input',
  };
  // 浏览器 watcher 有九种（chrome/firefox/edge/brave/vivaldi/arc/opera/yandex/orion），
  // 逐个列没意义，一律叫 Website
  function bucketLabel(kind) {
    if (kind.indexOf('web-') === 0) return 'Website';
    return BUCKET_LABELS[kind] || kind;
  }

  // 时间轴色块里的英文状态词
  var ITEM_LABELS = { 'not-afk': 'Active', afk: 'Away' };

  // 需要整行宽度的 custom_vis
  var WIDE_VIS = /\/pages\/dayline\//;

  var root = document.documentElement;
  root.setAttribute('data-aw-clean', 'on');
  Object.keys(CFG).forEach(function (k) {
    var attr = 'data-clean-' + k.replace(/[A-Z]/g, function (c) { return '-' + c.toLowerCase(); });
    root.setAttribute(attr, CFG[k] ? 'on' : 'off');
  });

  function txt(el) {
    return (el.textContent || '').trim();
  }

  // 官方路由的 "/" 跳转读的是 localStorage.landingpage（不是服务端 settings），
  // 新浏览器/清过缓存时会掉回 /home 那页广告墙 —— 这里直接兜住。
  (function landing() {
    var bare = !location.hash || location.hash === '#' || location.hash === '#/';
    var ls;
    try { ls = localStorage.getItem('landingpage'); } catch (e) { /* 隐私模式 */ }
    if (!bare && ls) return;
    fetch('/api/0/info')
      .then(function (r) { return r.json(); })
      .then(function (info) {
        var path = '/activity/' + info.hostname + '/view/';
        try { localStorage.setItem('landingpage', path); } catch (e) { /* noop */ }
        if (bare) location.hash = '#' + path;
      })
      .catch(function () { /* aw-server 没起来，随它去 */ });
  })();

  function tag() {
    // 官方 dark 主题是运行时注入 /dark.css，跟着切调色板
    root.setAttribute('data-clean-theme', document.querySelector('link[href*="dark.css"]') ? 'dark' : 'light');

    // Activity 页面根节点：第一个以 "Activity" 开头的 h3 的父元素
    var headings = document.querySelectorAll('#wrapper h3, #app h3');
    for (var i = 0; i < headings.length; i++) {
      if (/^Activity\b/.test(txt(headings[i])) && headings[i].parentElement) {
        headings[i].parentElement.setAttribute('data-clean-activity', '');
      }
    }

    var act = document.querySelector('[data-clean-activity]');
    if (act) {
      act.querySelectorAll('li').forEach(function (li) {
        if (/^Host:/.test(txt(li))) li.setAttribute('data-clean-host', '');
      });

      act.querySelectorAll(':scope > svg').forEach(function (svg) {
        svg.setAttribute('data-clean-periodbars', '');
      });

      var tabs = act.querySelector('ul.nav-tabs');
      if (tabs) {
        tabs.setAttribute('data-clean-tabs', '');
        tabs.querySelectorAll('li').forEach(function (li) {
          if (/New view/.test(txt(li))) li.setAttribute('data-clean-newview', '');
        });
      }

      act.querySelectorAll('button').forEach(function (b) {
        var t = txt(b);
        if (/^Filters\b/.test(t)) b.setAttribute('data-clean-filtersbtn', '');
        if (/^Edit view\b/.test(t)) (b.parentElement || b).setAttribute('data-clean-editview', '');
      });
    }

    // 图表网格（每个 vis 是 .col-md-6.col-lg-4.p-3）
    document.querySelectorAll('.row').forEach(function (r) {
      if (r.querySelector(':scope > .col-lg-4.p-3')) r.setAttribute('data-clean-grid', '');
    });

    // 官方的 isVisLarge 把「整宽」写死成 sunburst_clock / vis_timeline，custom_vis 配不出来，
    // 这里按 iframe 的 src 认出 dayline 自己撑成整行
    document.querySelectorAll('[data-clean-grid] iframe').forEach(function (f) {
      if (WIDE_VIS.test(f.getAttribute('src') || '')) {
        var col = f.closest('[class*="col-"]');
        if (col) col.setAttribute('data-clean-wide', '');
      }
    });

    // Score 卡：标出来好单独限制列表长度
    document.querySelectorAll('[data-clean-grid] > [class*="col-"] > div').forEach(function (c) {
      if (/Your total score today is/.test(txt(c))) c.setAttribute('data-clean-score', '');
    });

    // Score 卡的每一行：打上完整分类名，供点击联动用
    document.querySelectorAll('[data-clean-score] div.mt-2').forEach(function (row) {
      if (row.hasAttribute('data-clean-scorerow')) return;
      var flex = row.querySelector('.d-flex');
      var box = flex && flex.firstElementChild;   // 左半边：第 1 行叶子名，第 2 行父级路径
      if (!box) return;
      var kids = box.children;
      var leaf = kids[0] ? txt(kids[0]) : '';
      var parent = kids[1] ? txt(kids[1]) : '';
      if (!leaf) return;
      var full = parent ? parent + ' > ' + leaf : leaf;
      row.setAttribute('data-clean-scorerow', full);
    });

    // 有时长数据就贴上去；低于阈值的条目整行隐藏
    if (awDur) {
      document.querySelectorAll('[data-clean-scorerow]').forEach(function (row) {
        var sec = awDur[row.getAttribute('data-clean-scorerow')];
        if (sec === undefined) return;
        row.toggleAttribute('data-clean-small', sec < SMALL);
        var flex = row.querySelector('.d-flex');
        var right = flex && flex.lastElementChild;
        if (!right) return;
        var el = right.querySelector('.aw-dur');
        if (!el) {
          el = document.createElement('div');
          el.className = 'aw-dur';
          right.appendChild(el);
        }
        var txtNew = fmtDur(sec);
        if (el.textContent !== txtNew) el.textContent = txtNew;
      });
    }

    // 只干掉通知类横幅，保留 "missing data from a required watcher" 这种有用告警
    document.querySelectorAll('.alert').forEach(function (a) {
      if (/uncategorized|new release|new version|satisfied|satisfaction/i.test(txt(a))) {
        a.setAttribute('data-clean-notice', '');
      }
    });

    document.querySelectorAll('[data-clean-grid] i, [data-clean-grid] em, [data-clean-grid] .small').forEach(function (el) {
      if (/^Buckets with no events/.test(txt(el))) el.setAttribute('data-clean-timelinehint', '');
    });

    // 时间轴左侧 bucket id 太长：aw-watcher-web-chrome_<host> → Website
    if (CFG.shortBucketNames) {
      document.querySelectorAll('.vis-labelset .vis-inner').forEach(function (el) {
        var m = /^aw-watcher-([a-z0-9-]+)_/.exec(txt(el));
        if (m) el.textContent = bucketLabel(m[1]);
      });
      // 色块里的 not-afk / afk 也换成人话
      document.querySelectorAll('.vis-item-content').forEach(function (el) {
        var t = txt(el);
        if (ITEM_LABELS[t]) el.textContent = ITEM_LABELS[t];
      });
    }
  }

  // custom_vis 的 iframe：自己汇报高度 + 用 props.title 当卡片标题
  window.addEventListener('message', function (e) {
    if (e.origin !== location.origin || !e.data) return;
    if (e.data.type === 'aw-rollup-durations') { awDur = e.data.map; schedule(); return; }
    if (e.data.type !== 'aw-rollup-height') return;
    document.querySelectorAll('[data-clean-grid] iframe').forEach(function (f) {
      if (f.contentWindow !== e.source) return;
      f.style.height = Math.max(160, e.data.height) + 'px';
      var card = f.closest('[class*="col-"]') && f.closest('[class*="col-"]').querySelector('h5');
      if (card && e.data.title) card.textContent = e.data.title;
    });
  });

  // Score 卡条目悬停 → 右边环图高亮（和把鼠标放在扇区上完全一样，移开即恢复）
  function pushHighlight(name) {
    document.querySelectorAll('[data-clean-grid] iframe').forEach(function (f) {
      try { f.contentWindow.postMessage({ type: 'aw-rollup-highlight', name: name }, location.origin); } catch (e) {}
    });
  }
  var awDur = null;          // 分类 → 秒
  var SMALL = 20 * 60;       // 低于 20min 的条目不显示
  function fmtDur(sec) {
    var h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
    if (m === 60) { h += 1; m = 0; }
    return h ? h + 'h' + (m ? m + 'm' : '') : m + 'm';
  }

  var hoveredRow = null;
  document.addEventListener('mouseover', function (e) {
    var row = e.target.closest && e.target.closest('[data-clean-scorerow]');
    if (!row || row === hoveredRow) return;
    hoveredRow = row;
    row.setAttribute('data-clean-sel', '');
    pushHighlight(row.getAttribute('data-clean-scorerow'));
  });
  document.addEventListener('mouseout', function (e) {
    if (!hoveredRow) return;
    var to = e.relatedTarget;
    if (to && to.closest && to.closest('[data-clean-scorerow]') === hoveredRow) return;
    hoveredRow.removeAttribute('data-clean-sel');
    hoveredRow = null;
    pushHighlight(null);
  });

  var queued = false;
  function schedule() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(function () {
      queued = false;
      try { tag(); } catch (e) { console.warn('[aw-clean]', e); }
    });
  }

  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  document.addEventListener('DOMContentLoaded', schedule);
  window.addEventListener('hashchange', schedule);
  schedule();

  // Bundle 哈希会随 ActivityWatch 升级变化 —— 没挂载说明 index.html 过期了
  setTimeout(function () {
    var app = document.getElementById('app');
    if (app && app.children.length === 0 && !document.getElementById('wrapper')) {
      app.innerHTML =
        '<div style="font:14px/1.6 system-ui;padding:2rem;max-width:40rem;margin:0 auto">' +
        '<h3>页面没加载起来</h3><p>多半是 ActivityWatch 升级过了，bundle 文件名变了。' +
        '在终端跑一次 <code>~/WorkSpace/toolbox/aw-custom/clean/build.sh</code> 重新生成 index.html，然后刷新。</p>' +
        '<p><a href="/">← 回官方界面</a></p></div>';
    }
  }, 5000);
})();
