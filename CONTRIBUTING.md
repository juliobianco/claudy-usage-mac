# Contributing

Thanks for looking. A change can be a skin, a translation, a bug report or code. Small is welcome.

## Build and test

```sh
S=$HOME/Library/Caches/claudy-build
swift build --scratch-path $S
swift test  --scratch-path $S
./scripts/bundle.sh          # installs ~/Applications/ClaudyUsage.app
```

Build outside `~/Documents` (the scripts do): macOS adds file attributes there that break `codesign`. [CLAUDE.md](CLAUDE.md) lists the layout, the commands and the problems that already cost time. Read it before changing the data layer.

## What to know

- **Two targets.** `ClaudyCore` has no UI and is unit-tested; `ClaudyUsage` is SwiftUI. Logic goes in the core, with a test.
- **Text.** Never hard-code a string a user sees: add the key to `Sources/ClaudyUsage/Strings.swift` in **both** languages (`L.t("key", args)`). A new language is one more table there and in `StringsClaude.swift`.
- **Skins and animations.** [docs/CREATING-ART.md](docs/CREATING-ART.md). A skin is a `.txt` file in `Sources/ClaudyUsage/skins/`.
- **Style.** Match the file you are in: comments say why, in English; one file per domain; no new dependencies for something a few lines can do.
- **No credentials, ever.** The app does not read the Keychain or any token, and a change that does will not be merged. `claude` finds its own login.

## Pictures

Screenshots and GIFs are made by the app with made-up data (`CLAUDY_DEMO=1`) or with real use and names replaced (`CLAUDY_REDACT=1`): see [the screenshot and GIF tools](docs/GUIDE.md#development). **Never put real project names, branches, session names, e-mails or paths in a picture.**

## Pull requests

Say what changed and why, keep it to one thing, add or update a test when there is logic, and update the [CHANGELOG](CHANGELOG.md) under *Unreleased*. If you are not sure it fits, open an issue first.

Everything here is under the [MIT license](LICENSE).
