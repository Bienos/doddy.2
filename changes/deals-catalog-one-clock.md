Messaging leaflet catalog: the "is a chain due" check and the row it reads now use the same clock (the pass's `now()`), so the catalog test no longer depends on the time of day it runs.
Ran: `npm run build` and the full `npm test` in `server/messaging/` against a local Postgres 16 (981 pass, 0 fail). Not run: the live service.
