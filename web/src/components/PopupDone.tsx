import { useEffect } from "react";
import { closeSelf, tellOpener } from "../auth/popup.js";
import { useI18n } from "../i18n/i18n.js";
import { DoddyFigure } from "./Brand.js";

/**
 * What the small sign-in window shows once the server has signed this browser in (auth/popup.ts):
 * it tells the page that opened it, which asks the server for itself, and closes. If the browser
 * keeps the window open, the page says so and offers the button.
 */
export function PopupDone() {
  const { t } = useI18n();
  useEffect(() => {
    tellOpener({ type: "signedIn" });
    closeSelf();
  }, []);
  return (
    <main id="main" className="centered popup-done">
      <DoddyFigure size={88} />
      <h1>{t("popup.doneTitle")}</h1>
      <p className="lead">{t("popup.doneBody")}</p>
      <button type="button" className="button" onClick={closeSelf}>
        {t("popup.closeButton")}
      </button>
    </main>
  );
}
