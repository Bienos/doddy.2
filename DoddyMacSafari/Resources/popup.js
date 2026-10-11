// Save to Doddy: popup (ADR-353).
//
// Runs only when the user clicks the toolbar button. Reads the active tab's title, address and
// selected text (nothing else from the page) through activeTab, shows them, and on "Send to
// Doddy" hands them to the extension's native handler, which leaves a clip in the Mac clip
// inbox. Nothing is saved until the user presses Save in the Doddy app. No network request is
// made anywhere in this extension, and nothing is stored here.
"use strict";

(function () {
  var DISPLAY_SELECTION_LIMIT = 600;
  var api = typeof browser !== "undefined" ? browser : null;

  var els = {};
  [
    "heading", "loading", "page", "titleLabel", "pageTitle", "urlLabel", "pageUrl",
    "selectionBlock", "selectionLabel", "selectionText", "notSavedNote", "result",
    "sendButton", "cancelButton"
  ].forEach(function (id) { els[id] = document.getElementById(id); });

  var clip = null;
  var sending = false;

  function text(key) {
    var value = api ? api.i18n.getMessage(key) : "";
    return value || "";
  }

  function setText(el, key) {
    el.textContent = text(key);
  }

  function showResult(key) {
    els.result.textContent = text(key);
    els.result.hidden = false;
  }

  function finishWithoutSending(key) {
    els.sendButton.hidden = true;
    setText(els.cancelButton, "closeButton");
    showResult(key);
    els.cancelButton.focus();
  }

  function truncateForDisplay(value) {
    var characters = Array.from(value);
    if (characters.length <= DISPLAY_SELECTION_LIMIT) { return value; }
    return characters.slice(0, DISPLAY_SELECTION_LIMIT).join("") + "…";
  }

  // Runs inside the page, once, because the user clicked. Returns only these three values.
  function readPage() {
    return {
      title: document.title,
      url: location.href,
      selection: String(getSelection())
    };
  }

  function show(read) {
    clip = {
      title: typeof read.title === "string" ? read.title : "",
      url: typeof read.url === "string" ? read.url : "",
      selection: typeof read.selection === "string" ? read.selection : ""
    };
    els.pageTitle.textContent = clip.title || text("noTitle");
    els.pageUrl.textContent = clip.url;
    if (clip.selection.trim() !== "") {
      els.selectionText.textContent = truncateForDisplay(clip.selection);
      els.selectionBlock.hidden = false;
    }
    els.loading.hidden = true;
    els.page.hidden = false;
    els.sendButton.hidden = false;
    els.sendButton.focus();
  }

  async function load() {
    try {
      var tabs = await api.tabs.query({ active: true, currentWindow: true });
      var tab = tabs && tabs[0];
      if (!tab || tab.id === undefined) { throw new Error("no tab"); }
      var results = await api.scripting.executeScript({ target: { tabId: tab.id }, func: readPage });
      var read = results && results[0] && results[0].result;
      if (!read) { throw new Error("no result"); }
      show(read);
    } catch (error) {
      els.loading.hidden = true;
      finishWithoutSending("cantRead");
    }
  }

  function resultKey(reply) {
    var status = reply && reply.status;
    if (status === undefined && reply && reply.message) { status = reply.message.status; }
    switch (status) {
      case "sent": return "resultSent";
      case "full": return "resultFull";
      case "not_set_up": return "resultNotSetUp";
      case "nothing": return "resultNothing";
      default: return "resultFailed";
    }
  }

  async function send() {
    if (sending || !clip || els.sendButton.hidden) { return; }
    sending = true;
    els.sendButton.disabled = true;
    els.result.hidden = true;
    var key;
    try {
      var reply = await api.runtime.sendNativeMessage("application.id", {
        title: clip.title,
        url: clip.url,
        selection: clip.selection
      });
      key = resultKey(reply);
    } catch (error) {
      key = "resultFailed";
    }
    sending = false;
    els.sendButton.disabled = false;
    if (key === "resultFailed") {
      // Nothing was saved; the user may try again.
      showResult(key);
      els.sendButton.focus();
    } else {
      finishWithoutSending(key);
    }
  }

  function cancel() {
    window.close();
  }

  function init() {
    if (!api) { return; }
    var language = api.i18n.getUILanguage();
    if (language) { document.documentElement.lang = language; }
    document.title = text("extensionName");
    setText(els.heading, "extensionName");
    setText(els.loading, "loading");
    setText(els.titleLabel, "titleLabel");
    setText(els.urlLabel, "addressLabel");
    setText(els.selectionLabel, "selectionLabel");
    setText(els.notSavedNote, "notSavedNote");
    setText(els.sendButton, "sendButton");
    setText(els.cancelButton, "cancelButton");

    els.sendButton.addEventListener("click", send);
    els.cancelButton.addEventListener("click", cancel);
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        event.preventDefault();
        cancel();
      } else if (event.key === "Enter" && document.activeElement !== els.cancelButton) {
        event.preventDefault();
        send();
      }
    });

    load();
  }

  init();
})();
