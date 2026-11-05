// Text for the scripts, in the page's language (ADR-460). doddyT("English text") returns the
// translation from window.DODDY_I18N, which a page in another language loads from /i18n/<code>.js
// before this file's callers run; with none, it returns the English text. "{name}" in a text is
// filled from the values passed in: doddyT("Card {n}", { n: 3 }).
(function () {
  "use strict";
  function doddyT(text, values) {
    var table = window.DODDY_I18N || {};
    var out = Object.prototype.hasOwnProperty.call(table, text) ? table[text] : text;
    if (values) {
      out = out.replace(/\{(\w+)\}/g, function (whole, name) {
        return Object.prototype.hasOwnProperty.call(values, name) ? String(values[name]) : whole;
      });
    }
    return out;
  }
  window.doddyT = doddyT;
})();
