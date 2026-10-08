.PHONY: project test-core ci ci-core
project:        ## generate Doddy.xcodeproj from project.yml (macOS, needs xcodegen)
	xcodegen generate --spec project.yml
test-core:      ## Swift package tests (any platform with Swift 6)
	swift test --package-path Packages/DoddyCore $(if $(filter Linux,$(shell uname)),-Xswiftc -DSQLITE_DISABLE_SNAPSHOT)
ci:             ## full checks; exits non-zero if anything cannot run
	scripts/ci.sh
ci-core:        ## checks that can run without Xcode; iOS app reported NOT RUN
	scripts/ci.sh --core-only
