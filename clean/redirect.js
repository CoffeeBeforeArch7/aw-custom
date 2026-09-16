// 只在官方界面根路径生效：把 / 和 /index.html 弹到精简版，hash 原样带过去。
// 放在 /pages/clean/ 下是因为官方 index.html 的 CSP 只允许 script-src 'self'（不允许内联脚本），
// 同源的这个文件是允许的。文件 404（比如取消了 custom_static 挂载）时老界面照常工作。
(function () {
  var p = location.pathname;
  if (p === "/" || p === "/index.html") {
    location.replace("/pages/clean/" + location.hash);
  }
})();
