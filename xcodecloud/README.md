# Xcode Cloud CLI workflow helpers

This folder holds workflow definitions that can be created without the Xcode UI. Use `scripts/xcodecloud/workflows.sh` to talk to the App Store Connect API via curl.

## Prerequisites

1. Create an App Store Connect API key that has access to Xcode Cloud. Collect:
   - `ASC_KEY_ID` (the key ID)
   - `ASC_ISSUER_ID` (team/issuer id)
   - `ASC_PRIVATE_KEY_PATH` pointing to the downloaded `AuthKey_XXXXXX.p8` file.
2. Set `APP_BUNDLE_ID` (currently `com.vanities.Roadtrip`).
3. Install `jq` and `openssl` (already available in macOS + Homebrew shells).

## Discover the IDs you need

```bash
ASC_KEY_ID=XXXX ASC_ISSUER_ID=YYYY ASC_PRIVATE_KEY_PATH=~/AuthKey_XXXX.p8 \
APP_BUNDLE_ID=com.vanities.Roadtrip \
./scripts/xcodecloud/workflows.sh list-prereqs
```

The command prints the app id, CI product id, SCM repository id, and the list of available Xcode/macOS images. Copy the identifiers you want to target and export them as variables:

```bash
export XCODE_VERSION_ID="Xcode15.4"
export MACOS_VERSION_ID="14F"
# optional overrides if you want to pin specific ids
export CI_PRODUCT_ID=...
export SCM_REPOSITORY_ID=...
```

## Create workflows from the templates

The JSON files inside `xcodecloud/workflows/` describe the workflow attributes (start condition, actions, etc.). Run:

```bash
ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_PRIVATE_KEY_PATH=... \
APP_BUNDLE_ID=com.vanities.Roadtrip \
XCODE_VERSION_ID="Xcode15.4" MACOS_VERSION_ID="14F" \
./scripts/xcodecloud/workflows.sh create
```

Each template will be posted to `POST /v1/ciWorkflows` and the script echoes the created workflow id. You can edit or add templates at any time; the script will blindly create new workflows in App Store Connect.

If you need to update an existing workflow, delete it in App Store Connect (or patch it with the API) before rerunning the script.
