import { Route, Routes } from "react-router";
import { useSession } from "./auth/session.js";
import { AppShell } from "./components/AppShell.js";
import { DoddyFigure } from "./components/Brand.js";
import { ErrorState, Loading } from "./components/States.js";
import { useI18n } from "./i18n/i18n.js";
import { ActivityPage } from "./pages/ActivityPage.js";
import { AppsPage } from "./pages/AppsPage.js";
import { DocumentsPage } from "./pages/DocumentsPage.js";
import { HomePage } from "./pages/HomePage.js";
import { LOGBOOK_ENABLED } from "./logbook/config.js";
import { LogbookPage } from "./pages/LogbookPage.js";
import { NotFoundPage } from "./pages/NotFoundPage.js";
import { SettingsPage } from "./pages/SettingsPage.js";
import { SignInPage } from "./pages/SignInPage.js";

/** Every page needs a session; without one, the sign-in page shows at whatever address was opened. */
export function App() {
  const { state, recheck } = useSession();
  const { t } = useI18n();

  if (state.status === "checking") {
    return (
      <main id="main" className="centered">
        <DoddyFigure size={72} />
        <Loading />
      </main>
    );
  }
  if (state.status === "unreachable") {
    return (
      <main id="main" className="centered">
        <DoddyFigure size={72} />
        <h1 className="visually-hidden">{t("app.name")}</h1>
        <ErrorState error={state.error} onRetry={recheck} />
      </main>
    );
  }
  if (state.status === "signedOut") return <SignInPage />;

  return (
    <AppShell>
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/documents" element={<DocumentsPage />} />
        <Route path="/apps" element={<AppsPage />} />
        <Route path="/activity" element={<ActivityPage />} />
        {LOGBOOK_ENABLED ? <Route path="/logbook" element={<LogbookPage />} /> : null}
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Routes>
    </AppShell>
  );
}
