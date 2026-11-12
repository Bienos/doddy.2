/* Google Analytics 4, only after the visitor says yes.
 *
 * GA sets cookies, so nothing from Google loads until the visitor taps "Allow" in the banner. "No thanks"
 * means it never loads. The choice is kept in localStorage on this device; "Analytics choices" in the
 * footer opens the banner again. Until the visitor allows it, any _ga cookies left from an earlier visit
 * are removed. Kept in this same-origin file so the production CSP needs no inline-script hash.
 *
 * Vercel Web Analytics (cookieless) is separate and runs regardless; see README.
 */
(function () {
  'use strict';

  // GA4 measurement ID from Google Analytics → Admin → Data streams.
  var GA_MEASUREMENT_ID = 'G-MRF40685L1';
  var KEY = 'doddy-analytics-consent';
  var GRANTED = 'granted';
  var DENIED = 'denied';

  if (!/^G-[A-Z0-9]+$/.test(GA_MEASUREMENT_ID)) return;

  // The page's language (site/i18n.js), English without it. i18n.js runs after this file on some pages, so
  // init() waits for DOMContentLoaded, when every deferred script has run. Each text is passed to this
  // function directly, in double quotes, so tools/build_site_i18n.py finds it.
  function doddyT(text) { return typeof window.doddyT === 'function' ? window.doddyT(text) : text; }

  function readChoice() {
    try { return localStorage.getItem(KEY); } catch (e) { return null; }
  }
  function saveChoice(value) {
    try { localStorage.setItem(KEY, value); } catch (e) { /* storage blocked: ask again next visit, load nothing */ }
  }

  var loaded = false;
  function gtag() { window.dataLayer.push(arguments); }

  function loadGa() {
    window.dataLayer = window.dataLayer || [];
    if (loaded) {
      gtag('consent', 'update', { analytics_storage: 'granted' });
      return;
    }
    loaded = true;
    window.gtag = gtag;
    // The banner asks about measuring visits only: nothing for ads.
    gtag('consent', 'default', {
      analytics_storage: 'granted',
      ad_storage: 'denied',
      ad_user_data: 'denied',
      ad_personalization: 'denied'
    });
    gtag('js', new Date());
    gtag('config', GA_MEASUREMENT_ID, {
      allow_google_signals: false,
      allow_ad_personalization_signals: false
    });
    var s = document.createElement('script');
    s.async = true;
    s.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(GA_MEASUREMENT_ID);
    document.head.appendChild(s);
  }

  // Removes GA's cookies (_ga, _ga_<stream>) on this host and its parent domain.
  function clearGaCookies() {
    var host = location.hostname;
    var parent = host.split('.').slice(-2).join('.');
    document.cookie.split(';').forEach(function (c) {
      var name = c.split('=')[0].trim();
      if (name !== '_ga' && name.indexOf('_ga_') !== 0) return;
      [host, '.' + host, '.' + parent, ''].forEach(function (d) {
        document.cookie = name + '=; Max-Age=0; path=/' + (d ? '; domain=' + d : '');
      });
    });
  }

  function stopGa() {
    if (loaded) gtag('consent', 'update', { analytics_storage: 'denied' });
    clearGaCookies();
  }

  var banner;
  function hideBanner() { if (banner) banner.hidden = true; }

  function button(label, value, extraClass) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'button small' + (extraClass ? ' ' + extraClass : '');
    b.setAttribute('data-consent', value);
    b.textContent = label;
    return b;
  }

  function showBanner(focus) {
    if (!banner) {
      banner = document.createElement('section');
      banner.className = 'consent';
      banner.setAttribute('aria-label', doddyT("Analytics choice"));
      var text = document.createElement('p');
      text.textContent = doddyT("Can we count your visit with Google Analytics? It sets cookies. Nothing loads from Google unless you say yes, and you can change your mind at the bottom of any page.");
      var actions = document.createElement('div');
      actions.className = 'consent-actions';
      actions.appendChild(button(doddyT("Allow"), GRANTED));
      actions.appendChild(button(doddyT("No thanks"), DENIED, 'quiet'));
      banner.appendChild(text);
      banner.appendChild(actions);
      banner.addEventListener('click', function (e) {
        var btn = e.target.closest('[data-consent]');
        if (!btn) return;
        var value = btn.getAttribute('data-consent') === GRANTED ? GRANTED : DENIED;
        saveChoice(value);
        if (value === GRANTED) loadGa(); else stopGa();
        hideBanner();
      });
      document.body.appendChild(banner);
    }
    banner.hidden = false;
    if (focus) banner.querySelector('button').focus();
  }

  function init() {
    // Footer: the sentence about Google Analytics, and the button that asks again.
    document.querySelectorAll('[data-ga-note]').forEach(function (el) { el.hidden = false; });
    document.querySelectorAll('[data-analytics-choices]').forEach(function (el) {
      el.addEventListener('click', function (e) { e.preventDefault(); showBanner(true); });
    });

    var choice = readChoice();
    if (choice === GRANTED) {
      loadGa();
      return;
    }
    clearGaCookies();
    if (choice !== DENIED) showBanner(false);
  }

  var started = false;
  function start() {
    if (started) return;
    started = true;
    init();
  }
  if (document.readyState === 'complete') start();
  else {
    document.addEventListener('DOMContentLoaded', start);
    window.addEventListener('load', start);
  }
})();
