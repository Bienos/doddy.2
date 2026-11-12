-- The leaflet catalog (owner, 12 Nov 2026; decision docs/decisions/2026-11-12-leaflet-catalog.md): Doddy reads each
-- chain's current leaflets once, in the background, for everyone, and keeps what it read; a search matches the
-- person's items against it in code instead of reading every chain again. Only the shops' published leaflets and the
-- reader's read of their pages are kept: nothing about any person, no item anyone asked for.
-- New tables only: safe to apply on a live database. Nothing reads them while DEALS_CATALOG_ENABLED is "0".

-- One row per chain: the last good scan's snapshot (its leaflets, data products and page reads, as the code parsed
-- them), and when the chain was last tried. A failed scan updates only attempted_at and last_result.
CREATE TABLE leaflet_catalog (
  chain         text PRIMARY KEY CHECK (chain ~ '^[a-z]{2,20}$'),
  snapshot      jsonb,
  scanned_at    timestamptz,
  attempted_at  timestamptz NOT NULL,
  last_result   text NOT NULL CHECK (length(last_result) BETWEEN 1 AND 80),
  CHECK ((snapshot IS NULL) = (scanned_at IS NULL))
);

-- What the reader read on one leaflet page, so the next scan doesn't pay for it again. The key is a hash of the
-- leaflet's address and dates and the page image's address. `read` is null while the page couldn't be read; after
-- two failed attempts the scan leaves it. Rows unused for 30 days are deleted by the scan.
CREATE TABLE leaflet_page_reads (
  chain     text NOT NULL CHECK (chain ~ '^[a-z]{2,20}$'),
  page_key  text NOT NULL CHECK (page_key ~ '^[0-9a-f]{32}$'),
  read      jsonb,
  attempts  smallint NOT NULL DEFAULT 1 CHECK (attempts BETWEEN 1 AND 10),
  read_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (chain, page_key)
);
CREATE INDEX leaflet_page_reads_read_at ON leaflet_page_reads (read_at);
