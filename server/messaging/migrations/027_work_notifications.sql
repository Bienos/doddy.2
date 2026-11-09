-- Wake-ups for the worker (research item 7). The worker's queue loops now wait longer between looks while
-- nothing is queued; these triggers tell it at once when a message, errand or studio job is queued, so a longer
-- wait never delays real work. A notification carries only a topic name (never a row, id or text), is delivered
-- when the queuing transaction commits, and nothing depends on it arriving: the loops still poll as a fallback.
-- New function and triggers only: safe to apply on a live database; dropping them returns to fixed polling.

CREATE FUNCTION doddy_notify_work() RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify('doddy_work', TG_ARGV[0]);
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER outbound_messages_wake
  AFTER INSERT OR UPDATE OF state ON outbound_messages
  FOR EACH ROW WHEN (NEW.state = 'queued')
  EXECUTE FUNCTION doddy_notify_work('dispatch');

CREATE TRIGGER errands_wake
  AFTER INSERT OR UPDATE OF state ON errands
  FOR EACH ROW WHEN (NEW.state = 'queued')
  EXECUTE FUNCTION doddy_notify_work('errand');

CREATE TRIGGER studio_items_wake
  AFTER INSERT OR UPDATE OF state ON studio_items
  FOR EACH ROW WHEN (NEW.state = 'queued')
  EXECUTE FUNCTION doddy_notify_work('studio');
