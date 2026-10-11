/* Google Analytics 4, only after the visitor says yes.
 *
 * GA sets cookies, so nothing from Google loads until the visitor taps "Allow" in the
 * banner. The choice is kept in localStorage on this device; "Analytics choices" in the
 * footer reopens the banner. With no measurement ID set, this file does nothing at all:
 * no banner, no footer sentence, no request to Google.
 *
 * Vercel Web Analytics (cookieless) is separate and runs regardless; see README.
 */
(function () {
  'use strict';

  // GA4 measurement ID from Google Analytics → Admin → Data streams, e.g. 'G-ABC123DEF4'.
  var GA_MEASUREMENT_ID = 'G-WQXYVSGD4Q';
  var KEY = 'doddy-analytics-consent';

  if (!/^G-[A-Z0-9]+$/.test(GA_MEASUREMENT_ID)) return;

  function readChoice() {
    try { return localStorage.getItem(KEY); } catch (e) { return null; }
  }
  function saveChoice(value) {
    try { localStorage.setItem(KEY, value); } catch (e) { /* private mode: ask again next visit */ }
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

  function stopGa() {
    if (loaded) gtag('consent', 'update', { analytics_storage: 'denied' });
    // Remove the cookies GA already set (_ga, _ga_<stream>) on this host and its parent domain.
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

  var banner;
  function hideBanner() { if (banner) banner.hidden = true; }

  function showBanner(focus) {
    if (!banner) {
      banner = document.createElement('section');
      banner.className = 'consent';
      banner.setAttribute('aria-label', 'Analytics choice');
      banner.innerHTML =
        '<p>Can we use Google Analytics? It sets cookies so we can see how people find and use this site. ' +
        'Nothing is sent to Google unless you say yes, and you can change your mind in the footer.</p>' +
        '<div class="consent-actions">' +
        '<button type="button" class="button small" data-consent="granted">Allow</button>' +
        '<button type="button" class="button small quiet" data-consent="denied">No thanks</button>' +
        '</div>';
      banner.addEventListener('click', function (e) {
        var btn = e.target.closest('[data-consent]');
        if (!btn) return;
        var value = btn.getAttribute('data-consent');
        saveChoice(value);
        if (value === 'granted') loadGa(); else stopGa();
        hideBanner();
      });
      document.body.appendChild(banner);
    }
    banner.hidden = false;
    if (focus) banner.querySelector('button').focus();
  }

  function init() {
    // Footer: say Google Analytics is in use (only when it is configured) and offer the choice again.
    document.querySelectorAll('[data-ga-note]').forEach(function (el) { el.hidden = false; });
    document.querySelectorAll('[data-analytics-choices]').forEach(function (el) {
      el.addEventListener('click', function (e) { e.preventDefault(); showBanner(true); });
    });

    var choice = readChoice();
    if (choice === 'granted') loadGa();
    else if (choice !== 'denied') showBanner();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
