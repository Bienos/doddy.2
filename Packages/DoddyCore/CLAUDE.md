# DoddyCore: shared rules for every platform
iPhone, Watch and Mac all use this package. A change here affects all of them.
- **Must stay free of UI:** Foundation, GRDB and CryptoKit only, so it builds and tests on Linux.
- **Test:** `make test-core`. On Linux the Makefile adds the SQLite flags.
- **Say which platforms** a change touches (see `docs/platforms/README.md`).

For local iteration, use a relevant `swift test --filter` when it covers the change. Run `make test-core` when broader package coverage is warranted; CI retains its configured package suite. This replaces the unconditional local test instruction above.
