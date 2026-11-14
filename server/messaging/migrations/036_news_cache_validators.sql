-- Conditional feed fetches (decision docs/decisions/2026-11-13-news-more-sources.md, src/news/reader.ts). The shared
-- news cache keeps each publisher's validators from its last answer (ETag, Last-Modified), so the next fetch asks
-- "changed since?" and an unchanged feed answers 304 with no body. They are the publisher's, about a public feed;
-- news_cache is not linked to any account and its key is a hash of the address (ADR-175). Nothing about a person.
-- Two nullable columns with no default on a small, shared cache table: no rewrite, safe to apply on a live database.
-- The previous release ignores them.

ALTER TABLE news_cache ADD COLUMN etag text CHECK (length(etag) <= 200);
ALTER TABLE news_cache ADD COLUMN last_modified text CHECK (length(last_modified) <= 200);
