.PHONY: project team test-core ci ci-core
team:           ## remember your Apple Developer Team ID for signing:  make team ID=ABCDE12345  (once)
	@test -n "$(ID)" || { echo "Usage: make team ID=<your 10-character Team ID>"; exit 1; }
	@printf 'DEVELOPMENT_TEAM = %s\n' "$(ID)" > Config/Team.local.xcconfig
	@echo "Saved. Run 'make project' and every target is signed with team $(ID)."
project:        ## generate Doddy.xcodeproj from project.yml (macOS, needs xcodegen)
	xcodegen generate --spec project.yml
test-core:      ## Swift package tests (any platform with Swift 6)
	swift test --package-path Packages/DoddyCore $(if $(filter Linux,$(shell uname)),-Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined)
ci:             ## full checks; exits non-zero if anything cannot run
	scripts/ci.sh
ci-core:        ## checks that can run without Xcode; iOS app reported NOT RUN
	scripts/ci.sh --core-only
