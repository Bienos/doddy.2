import { useI18n } from "../i18n/i18n.js";

/** The app's wordmark (ADR-562), drawn in the current text colour so it works on light and dark. */
export function Wordmark({ className }: { className?: string }) {
  const { t } = useI18n();
  return <span className={`wordmark ${className ?? ""}`} role="img" aria-label={t("app.name")} />;
}

/**
 * Doddy sitting cross-legged, the pose on the iPhone's calm Home (ADR-545), from the owner's pack
 * (WholeDoddy_crosslegged). Decorative: it never stands for an action or a state.
 */
export function DoddyFigure({ size = 120 }: { size?: number }) {
  return (
    <img
      className="doddy-figure"
      src="/brand/doddy-crosslegged@2x.png"
      srcSet="/brand/doddy-crosslegged@2x.png 2x, /brand/doddy-crosslegged@3x.png 3x"
      width={size}
      height={size * 1.5}
      alt=""
      decoding="async"
    />
  );
}
