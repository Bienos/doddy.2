import { Link } from "react-router";
import { PageHeader } from "../components/PageHeader.js";
import { useI18n } from "../i18n/i18n.js";

export function NotFoundPage() {
  const { t } = useI18n();
  return (
    <>
      <PageHeader title={t("notFound.title")} />
      <Link to="/">{t("notFound.home")}</Link>
    </>
  );
}
