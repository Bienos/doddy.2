-- Decision 2026-11-08-required-account: every Doddy user signs in with a Doddy account (a Supabase
-- user: Apple, Google or a code sent by email). An account here belongs to at most one of them, and
-- each Doddy account has at most one account here. NULL: an anonymous account from before.
ALTER TABLE accounts ADD COLUMN auth_subject TEXT UNIQUE;
