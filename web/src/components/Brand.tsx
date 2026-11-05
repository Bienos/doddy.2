import { useI18n } from "../i18n/i18n.js";

/** The app's wordmark (ADR-562), drawn in the current text colour so it works on light and dark. */
export function Wordmark({ className }: { className?: string }) {
  const { t } = useI18n();
  return <span className={`wordmark ${className ?? ""}`} role="img" aria-label={t("app.name")} />;
}

export type DoddyPose = "crosslegged" | "belly-reading" | "shush" | "wave" | "kneeling-inspect";

/**
 * One of Doddy's poses from the owner's pack (the app's WholeDoddy_* images, copied byte for byte by
 * tools/gen_web_assets.py). Home's is the cross-legged one from the iPhone's calm Home (ADR-545).
 * Decorative: it never stands for an action or a state.
 */
export function DoddyFigure({ size = 120, pose = "crosslegged", className }: { size?: number; pose?: DoddyPose; className?: string }) {
  return (
    <img
      className={`doddy-figure ${className ?? ""}`}
      src={`/brand/doddy-${pose}@2x.png`}
      srcSet={`/brand/doddy-${pose}@2x.png 2x, /brand/doddy-${pose}@3x.png 3x`}
      width={size}
      height={size * 1.5}
      alt=""
      decoding="async"
    />
  );
}
