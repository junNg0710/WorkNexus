/// Ported from: lib/features/mini_apps/presentation/util/mini_app_notifications.dart, mini_app_login_capability.dart
/// The scripts a mini app's page runs. They talk to the app through `window.webkit.messageHandlers.wnBridge.postMessage`,
/// which answers with a Promise; every call carries `__TOKEN__`, a secret only the main-frame script knows (a cross-origin
/// iframe cannot read it), and the app also checks the call came from the main frame.
enum MiniAppScripts {
    /// The bridge call both scripts share.
    private static let call = """
    const token = '__TOKEN__';
    const call = (name, ...args) => {
      try { return Promise.resolve(window.webkit.messageHandlers.wnBridge.postMessage({ name, token, args })); }
      catch (e) { return Promise.resolve(null); }
    };
    """

    /// Replaces the page's `Notification` (and `ServiceWorkerRegistration.showNotification` called from the page) with one
    /// that reports to the app, so a notification is an OS notification. The permission it reports is the one the user
    /// gave, asked the first time the page requests it; a page on another site than the app's is always denied.
    static let notifications = """
    (() => {
      if (window.__wnNotifications) return;
      window.__wnNotifications = true;
      \(call)
      let permission = 'default';
      call('miniAppNotificationState').then((p) => { if (p) permission = p; }).catch(() => {});
      const notify = (title, options) => {
        const o = options || {};
        call('miniAppNotify', String(title), String(o.body || ''), String(o.tag || ''));
      };
      class WNNotification extends EventTarget {
        constructor(title, options) {
          super();
          const o = options || {};
          this.title = String(title);
          this.body = String(o.body || '');
          this.icon = String(o.icon || '');
          this.tag = String(o.tag || '');
          this.data = o.data;
          this.onclick = this.onclose = this.onerror = this.onshow = null;
          notify(title, o);
          setTimeout(() => {
            const e = new Event('show');
            if (this.onshow) this.onshow(e);
            this.dispatchEvent(e);
          });
        }
        close() {}
        static get permission() { return permission; }
        static get maxActions() { return 0; }
        static requestPermission(callback) {
          return call('miniAppNotificationPermission').then((p) => {
            permission = p || 'denied';
            if (callback) callback(permission);
            return permission;
          });
        }
      }
      Object.defineProperty(window, 'Notification', { value: WNNotification, writable: true, configurable: true });
      if (window.ServiceWorkerRegistration) {
        ServiceWorkerRegistration.prototype.showNotification = function (title, options) {
          notify(title, options);
          return Promise.resolve();
        };
      }
    })();
    """

    /// Watches for ZenTao's login form — a visible, empty `password` field with the `account` field beside it; the form may
    /// be drawn after the page loads — asks once for the login, and puts it in those two fields as typed, so a framework's
    /// form sees it. Any other password field (one confirming a change, say) is left alone. Then signs in when the app says
    /// to: the form's submit button, else the form itself, else Enter in the password field. Asks again only after the form
    /// has gone and come back. It does nothing on a page that is not ZenTao's login page (the address says so).
    static let login = """
    (function () {
      \(call)
      var asked = false;
      var pending = false;
      function onLoginPage() {
        var last = location.pathname.split('/').pop() || '';
        if (last.indexOf('user-login') === 0) return true;
        var q = new URLSearchParams(location.search);
        return q.get('m') === 'user' && q.get('f') === 'login';
      }
      function visible(el) { return !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length); }
      function set(el, value) {
        var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
        setter.call(el, value);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      }
      function loginForm() {
        var passwords = [].slice.call(document.querySelectorAll('input[type=password][name=password]')).filter(visible);
        for (var i = 0; i < passwords.length; i++) {
          var root = passwords[i].form || document;
          var account = root.querySelector('input[name=account], #account');
          if (account && visible(account)) return { account: account, password: passwords[i] };
        }
        return null;
      }
      function submit(password) {
        var root = password.form || document;
        var button = [].slice.call(root.querySelectorAll('button[type=submit], input[type=submit]')).filter(visible)[0];
        if (button) { button.click(); return; }
        if (password.form && password.form.requestSubmit) { password.form.requestSubmit(); return; }
        ['keydown', 'keypress', 'keyup'].forEach(function (type) {
          password.dispatchEvent(new KeyboardEvent(type, { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
        });
      }
      function check() {
        if (!onLoginPage()) { asked = false; return; }
        var form = loginForm();
        if (!form) { asked = false; return; }
        if (asked || form.password.value) return;
        asked = true;
        call('miniAppLogin').then(function (login) {
          if (!login || form.password.value) return;
          if (!form.account.value) set(form.account, login.account);
          set(form.password, login.password);
          if (login.submit) setTimeout(function () { submit(form.password); }, 150);
        });
      }
      function schedule() {
        if (pending) return;
        pending = true;
        setTimeout(function () { pending = false; check(); }, 50);
      }
      new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
      check();
    })();
    """
}
