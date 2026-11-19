-- Content-free, bounded progress history. The errand row owns its retention and deletion.
ALTER TABLE errands ADD COLUMN progress jsonb;
