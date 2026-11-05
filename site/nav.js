// Phone menu for the nav (links are hidden below 820px). Loaded on every page. No storage, no network.
(() => {
  const button = document.querySelector(".menu-button");
  const sheet = document.querySelector("#menu-sheet");
  if (!button || !sheet) return;

  function setOpen(open) {
    sheet.classList.toggle("is-open", open);
    button.setAttribute("aria-expanded", String(open));
    button.setAttribute("aria-label", open ? doddyT("Close menu") : doddyT("Menu"));
  }
  button.addEventListener("click", () => setOpen(!sheet.classList.contains("is-open")));
  sheet.addEventListener("click", (event) => { if (event.target.closest("a")) setOpen(false); });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && sheet.classList.contains("is-open")) { setOpen(false); button.focus(); }
  });
  document.addEventListener("click", (event) => {
    if (sheet.classList.contains("is-open") && !sheet.contains(event.target) && !button.contains(event.target)) setOpen(false);
  });
  // Rotating a phone to landscape widens past the breakpoint: close it so it can't reopen stale.
  window.matchMedia("(min-width: 820px)").addEventListener("change", (event) => { if (event.matches) setOpen(false); });
})();
