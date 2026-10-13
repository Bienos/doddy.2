.PHONY: project project-iphone project-mac test-core ci ci-core
project:        ## generate Doddy.xcodeproj from project.yml (macOS, needs xcodegen)
	xcodegen generate --spec project.yml
project-iphone: ## generate DoddyiPhone.xcodeproj: iPhone/iPad app without the watch app
	xcodegen generate --spec project-iphone.yml
project-mac:    ## generate DoddyMac.xcodeproj: the Mac menu bar app and widget only
	xcodegen generate --spec project-mac.yml
test-core:      ## Swift package tests (any platform with Swift 6)
	swift test --package-path Packages/DoddyCore $(if $(filter Linux,$(shell uname)),-Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined)
ci:             ## full checks; exits non-zero if anything cannot run
	scripts/ci.sh
ci-core:        ## checks that can run without Xcode; iOS app reported NOT RUN
	scripts/ci.sh --core-only
