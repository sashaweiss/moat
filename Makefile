# Signing identity and notary profile for `make release`:
# {
#   "signingIdentity": "Developer ID Application: ...",
#   "notaryProfile": "..."
# }
IDENTITY := release-identity.json

CONTAINER := container

.PHONY: install test release image image-swift container-system

install:
	swift build --package-path MoatCLI -c release

test:
	swift test --package-path MoatKit
	swift test --package-path MoatCLI
	swift test --package-path MoatRelease
	xcodebuild build -project MoatGUI/MoatGUI.xcodeproj -scheme MoatGUI \
		-destination platform=macOS

# Extra moat-release flags go in ARGS, e.g. `make release ARGS=--dry-run`.
release: test
	@test -f $(IDENTITY) || { echo "missing $(IDENTITY)" >&2; exit 1; }
	identity=$$(jq -er .signingIdentity $(IDENTITY)) && \
	profile=$$(jq -er .notaryProfile $(IDENTITY)) && \
	swift run --package-path MoatRelease moat-release \
		--signing-identity "$$identity" --notary-profile "$$profile" \
		$(ARGS)

# Image builds skip the cache, so they always get the latest Claude Code.
image: container-system
	$(CONTAINER) build --no-cache -t moat:base -f images/moat-base.Containerfile images

image-swift: image
	$(CONTAINER) build --no-cache -t moat:swift -f images/moat-swift.Containerfile images

# Starts container's system if it isn't running. First start prompts to
# download a kernel.
container-system:
	@$(CONTAINER) system status >/dev/null 2>&1 || $(CONTAINER) system start
