import { type ReactNode, useEffect, useRef } from "react";
import { useLocation } from "react-router";

/**
 * The page's one heading. After a link inside the app it takes focus, so a screen reader
 * announces where the link led and keyboard users start at the top of the new page. On the first
 * page of a visit focus stays at the start of the document, where the skip link is.
 */
export function PageHeader({ title, lead, actions }: { title: string; lead?: ReactNode; actions?: ReactNode }) {
  const heading = useRef<HTMLHeadingElement>(null);
  const location = useLocation();
  useEffect(() => {
    // React Router gives the first location of a visit the key "default".
    if (location.key !== "default") heading.current?.focus({ preventScroll: false });
  }, [title, location.key]);
  return (
    <header className="page-header">
      <div>
        <h1 tabIndex={-1} ref={heading}>
          {title}
        </h1>
        {lead ? <p className="lead">{lead}</p> : null}
      </div>
      {actions ? <div className="page-actions">{actions}</div> : null}
    </header>
  );
}
