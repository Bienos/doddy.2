/**
 * Doddy waitlist receiver: a Google Apps Script web app bound to the "Doddy waitlist" sheet.
 * The landing page POSTs {"email", "page", "consent", "website"} as text/plain JSON; each new
 * email becomes one row on the "Signups" tab. Setup steps: site/README.md (Waitlist).
 *
 * Stores only what the form says it stores: time, email, page, consent version. No IP, no user agent.
 */
var SHEET_NAME = 'Signups';
var MAX_EMAIL = 254;
var EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function doPost(e) {
  var body;
  try {
    body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
  } catch (err) {
    return reply_({ ok: false, error: 'bad_request' });
  }

  // Honeypot: people never see or fill "website"; bots usually do. Pretend it worked.
  if (body.website) return reply_({ ok: true, status: 'added' });

  var email = String(body.email || '').trim().toLowerCase();
  if (!email || email.length > MAX_EMAIL || !EMAIL.test(email) || /^[=+\-@]/.test(email)) {
    return reply_({ ok: false, error: 'invalid_email' });
  }
  var page = cell_(body.page, 200);
  var consent = cell_(body.consent, 40);

  var lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) return reply_({ ok: false, error: 'busy' });
  try {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME);
    var existing = sheet.getRange('B:B').createTextFinder(email).matchEntireCell(true).findNext();
    if (existing) return reply_({ ok: true, status: 'already' });
    sheet.appendRow([new Date().toISOString(), email, page, consent]);
    return reply_({ ok: true, status: 'added' });
  } finally {
    lock.releaseLock();
  }
}

// Plain text only, never a formula: drop leading = + - @ and cap the length.
function cell_(value, max) {
  return String(value || '').replace(/^[=+\-@\s]+/, '').slice(0, max);
}

function reply_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
