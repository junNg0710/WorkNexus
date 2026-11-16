/// New (no Dart counterpart): the script behind the mini apps' saved passwords. It runs in the main frame only and in a
/// JavaScript world of its own (`MiniAppPasswordCapability.world`), so the page's scripts can neither read it, call its
/// functions nor reach its bridge; what it shares with the page is the document.
///
/// It never holds a saved password: it tells the app a sign-in form appeared (`wnPasswordForm`) and the app, having checked
/// the page's origin itself, fills the form by calling `__wnFillLogin` in this world. When the user sends the form it hands
/// what was typed to the app (`wnPasswordSubmit`), which asks before keeping anything.
enum MiniAppPasswordScripts {
    static let source = """
    (function () {
      if (window.__wnPasswords) return;
      window.__wnPasswords = true;
      const token = '__TOKEN__';
      const call = (name, ...args) => {
        try { return Promise.resolve(window.webkit.messageHandlers.wnBridge.postMessage({ name, token, args })); }
        catch (e) { return Promise.resolve(null); }
      };
      const MAX_REPORTS = 20;
      const known = new WeakSet();
      let current = null, reports = 0, pending = false, lastUser = '', sentAt = 0, sentFrom = null;

      function visible(el) {
        if (!el || el.disabled) return false;
        if (!(el.offsetWidth || el.offsetHeight || el.getClientRects().length)) return false;
        const style = getComputedStyle(el);
        return style.visibility !== 'hidden' && style.display !== 'none';
      }
      function isUser(el) {
        if (known.has(el)) return false;
        const type = (el.getAttribute('type') || 'text').toLowerCase();
        return type === 'text' || type === 'email' || type === 'tel';
      }
      function isPassword(el) { return el.type === 'password' || known.has(el); }
      function fields() { return [].slice.call(document.querySelectorAll('input')).filter(visible); }

      // The sign-in form on the page now: a visible password field, alone of its kind in its <form> (or, without one, on
      // the page: two of them are a sign-up or a change of password, which is left alone), with the closest visible
      // text / email / tel field before it as the user name. The user name is missing on a password-only step.
      function loginForm(preferred) {
        const all = fields();
        const passwords = all.filter(isPassword);
        if (!passwords.length) return null;
        const password = preferred && passwords.indexOf(preferred) >= 0 ? preferred : passwords[0];
        if (passwords.filter((el) => el.form === password.form).length > 1) return null;
        let username = null;
        for (let i = all.indexOf(password) - 1; i >= 0; i--) {
          if (isUser(all[i]) && all[i].form === password.form) { username = all[i]; break; }
        }
        return { username, password };
      }

      // Sets a field the way typing does: the element's own setter, then the events a framework listens for.
      function setValue(el, value) {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, value);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      }

      // Called by the app (in this world only). Fills the form on the page now, if the page is still the origin the
      // sign-in was saved on. Unless `force` (the user picked the sign-in), text already typed is never replaced.
      window.__wnFillLogin = function (origin, username, password, force) {
        if (location.origin !== origin) return false;
        const form = loginForm();
        if (!form) return false;
        const typedUser = form.username ? form.username.value : '';
        if (!force && (form.password.value || (typedUser && typedUser !== username))) return false;
        if (form.username && (force || !typedUser)) setValue(form.username, username);
        setValue(form.password, password);
        return true;
      };

      function check() {
        const form = loginForm();
        if (!form) { current = null; return; }
        known.add(form.password);
        if (current === form.password) return;
        current = form.password;
        if (reports++ >= MAX_REPORTS) return;
        call('wnPasswordForm', !form.password.value && !(form.username && form.username.value));
      }
      function schedule() {
        if (pending) return;
        pending = true;
        setTimeout(function () { pending = false; check(); }, 120);
      }

      // What was typed goes to the app when the form is sent. The app asks the user before keeping it.
      function capture(form) {
        if (!form || !form.password.value) return;
        const now = Date.now();
        if (sentFrom === form.password && now - sentAt < 1500) return;
        sentFrom = form.password; sentAt = now;
        call('wnPasswordSubmit', form.username ? form.username.value : lastUser, form.password.value);
      }
      // A user name typed on a step of its own (the password comes on the next one).
      function noteUser() {
        const users = fields().filter(isUser).filter((el) => el.value &&
          /user|login|email|account|phone/i.test([el.autocomplete, el.name, el.id, el.type].join(' ')));
        if (users.length === 1) lastUser = users[0].value;
      }
      function label(el) { return ((el.textContent || '') + (el.value || '') + (el.getAttribute('aria-label') || '')).trim(); }
      // A button that sends the form: in the password's <form>, or — without one — in a block around the password field.
      // Not a button inside the field's own wrapper (show / hide the password), nor one that resets.
      function sends(form, button) {
        const password = form.password;
        const text = label(button);
        if ((button.getAttribute('type') || '').toLowerCase() === 'reset' || !text) return false;
        if (/show|hide|reveal|visib|toggle|clear|forgot|reset|cancel|sign ?up|register|create/i.test(text)) return false;
        const wrapper = password.parentElement;
        if (wrapper && wrapper.contains(button) && wrapper.querySelectorAll('input').length === 1) return false;
        if (password.form) return password.form.contains(button) || button.form === password.form;
        let node = wrapper;
        for (let i = 0; i < 6 && node && node !== document.body && node !== document.documentElement; i++, node = node.parentElement) {
          if (node.contains(button)) return true;
        }
        return false;
      }

      document.addEventListener('submit', function (e) {
        const form = loginForm();
        if (form && (!form.password.form || form.password.form === e.target)) capture(form);
      }, true);
      document.addEventListener('keydown', function (e) {
        if (e.key !== 'Enter' || !e.target || e.target.tagName !== 'INPUT') return;
        const form = loginForm(isPassword(e.target) ? e.target : null);
        if (!form) { noteUser(); return; }
        if (e.target === form.password || e.target === form.username) capture(form);
      }, true);
      document.addEventListener('click', function (e) {
        const button = e.target && e.target.closest ? e.target.closest('button, input[type=submit], input[type=button], [role=button]') : null;
        if (!button) return;
        const form = loginForm();
        if (!form) { noteUser(); return; }
        if (sends(form, button)) capture(form);
      }, true);

      new MutationObserver(schedule).observe(document.documentElement, {
        childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'style', 'hidden', 'type', 'disabled']
      });
      window.addEventListener('hashchange', schedule);
      window.addEventListener('pageshow', schedule);
      check();
    })();
    """
}
