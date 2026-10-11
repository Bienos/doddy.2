.PHONY: project team test-core ci ci-core
team:           ## remember your Team ID:  make team ID=ABCDE12345 [FREE=1]  (once). No ID: reads it from your current Doddy.xcodeproj
	@id="$(ID)"; \
	[ -n "$$id" ] || id=$$(grep -ho 'DEVELOPMENT_TEAM = [A-Z0-9]\{10\}' Doddy.xcodeproj/project.pbxproj 2>/dev/null | head -1 | awk '{print $$3}'); \
	[ -n "$$id" ] || { echo "Usage: make team ID=<10-character Team ID> [FREE=1]"; exit 1; }; \
	printf 'DEVELOPMENT_TEAM = %s\n' "$$id" > Config/Team.local.xcconfig; \
	if [ -n "$(FREE)" ]; then printf 'DODDY_APP_ENTITLEMENTS =\nDODDY_WIDGET_ENTITLEMENTS =\nDODDY_SHARE_ENTITLEMENTS =\nDODDY_WATCH_ENTITLEMENTS =\n' >> Config/Team.local.xcconfig; echo "Free account: App Group off."; fi; \
	echo "Saved team $$id. Now run: make project"
project:        ## generate Doddy.xcodeproj from project.yml (macOS, needs xcodegen)
	xcodegen generate --spec project.yml
test-core:      ## Swift package tests (any platform with Swift 6)
	swift test --package-path Packages/DoddyCore $(if $(filter Linux,$(shell uname)),-Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined)
ci:             ## full checks; exits non-zero if anything cannot run
	scripts/ci.sh
ci-core:        ## checks that can run without Xcode; iOS app reported NOT RUN
	scripts/ci.sh --core-only
