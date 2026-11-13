# Shortcuts for working on AsterNUP. Everything here is a thin wrapper around scripts/.
.PHONY: help app run install uninstall dmg test icon project backend check clean

help:            ## Show this list
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

app:             ## Build build/AsterNUP.app (ad-hoc signed; set ASTERNUP_SIGN_IDENTITY to sign)
	scripts/make_app.sh

run: app         ## Build and open AsterNUP in a window
	open build/AsterNUP.app --args --windowed

install:         ## Build, install to ~/Applications and set up the backend (same as the one-line installer)
	scripts/install.sh

uninstall:       ## Remove AsterNUP.app (scripts/uninstall.sh --all also removes its data)
	scripts/uninstall.sh

dmg:             ## Build build/AsterNUP-<version>.dmg
	scripts/make_dmg.sh

test: backend    ## Run the automated checks (no dump, Xcode or controller needed)
	Tests/run_ui_tests.sh

icon:            ## Re-render Resources/App/AppIcon.icns
	swift scripts/make_icon.swift

project:         ## Regenerate AsterNUP.xcodeproj from project.yml (needs XcodeGen)
	xcodegen generate

backend:         ## Fetch the pinned nxnative backend
	scripts/fetch_backend.sh

check:           ## Check whether this Mac can build games
	scripts/check_toolchain.sh

clean:           ## Remove build products
	rm -rf build .build
