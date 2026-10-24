.PHONY: project project-iphone project-watch project-mac test-core ci ci-core
project:        ## generate Doddy.xcodeproj from project.yml: iPhone/iPad app (macOS, needs xcodegen)
	xcodegen generate --spec project.yml
project-iphone: ## generate DoddyiPhone.xcodeproj: iPhone/iPad app with only HealthKit (free Apple team)
	xcodegen generate --spec project-iphone.yml
# Apple Watch and Mac development are paused (ADR-572). Their targets still build when asked for
# on purpose: set ENABLE_WATCH=1 / ENABLE_MAC=1. Nothing else (CI, project.yml) builds them.
project-watch:  ## PAUSED: generate DoddyWithWatch.xcodeproj (iPhone app + Watch app); needs ENABLE_WATCH=1
	@test -n "$(ENABLE_WATCH)" || { echo "Apple Watch development is paused (ADR-572). To build it anyway: make project-watch ENABLE_WATCH=1" >&2; exit 1; }
	xcodegen generate --spec project-watch.yml
project-mac:    ## PAUSED: generate DoddyMac.xcodeproj (Mac menu bar app and widget); needs ENABLE_MAC=1
	@test -n "$(ENABLE_MAC)" || { echo "Mac development is paused (ADR-572). To build it anyway: make project-mac ENABLE_MAC=1" >&2; exit 1; }
	xcodegen generate --spec project-mac.yml
test-core:      ## Swift package tests (any platform with Swift 6)
	swift test --package-path Packages/DoddyCore $(if $(filter Linux,$(shell uname)),-Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined)
ci:             ## full checks; exits non-zero if anything cannot run
	scripts/ci.sh
ci-core:        ## checks that can run without Xcode; iOS app reported NOT RUN
	scripts/ci.sh --core-only
