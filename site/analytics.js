/* Google Analytics 4 (the Google tag), loaded on every page.
 *
 * This is the same tag Google gives for measurement ID G-MRF40685L1, kept in this same-origin
 * file so the production CSP needs no inline-script hash. It sets cookies and runs on every
 * visit; there is no consent banner. The footer says so.
 *
 * Vercel Web Analytics (cookieless) is separate and runs regardless; see README.
 */
(function () {
  'use strict';

  // GA4 measurement ID from Google Analytics → Admin → Data streams.
  var GA_MEASUREMENT_ID = 'G-MRF40685L1';

  window.dataLayer = window.dataLayer || [];
  function gtag() { window.dataLayer.push(arguments); }
  window.gtag = gtag;
  gtag('js', new Date());
  gtag('config', GA_MEASUREMENT_ID);

  var s = document.createElement('script');
  s.async = true;
  s.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(GA_MEASUREMENT_ID);
  document.head.appendChild(s);
})();
