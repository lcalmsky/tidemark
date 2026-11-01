<p align="center"><img src="docs/images/logo.png" width="128" alt="Tidemark logo"></p>

<h1 align="center">Tidemark</h1>

<p align="center">See your Claude plan usage limits from the macOS menu bar.</p>

<p align="center"><a href="README.md">한국어</a> · <b>English</b></p>

<p align="center">
  <a href="https://github.com/lcalmsky/tidemark/releases/latest"><img src="https://img.shields.io/github/v/release/lcalmsky/tidemark?label=release&color=5b6cff" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-111111" alt="macOS 13 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2ea44f" alt="MIT license"></a>
</p>

<p align="center"><img src="docs/images/menubar.png" alt="Tidemark drawing a ring, percentage, and time to reset for each limit in the menu bar"></p>

<br>

## Quick start

```sh
brew tap lcalmsky/tidemark https://github.com/lcalmsky/tidemark
brew trust lcalmsky/tidemark
brew install lcalmsky/tidemark/tidemark
brew services start lcalmsky/tidemark/tidemark
```

A ring for each limit appears on the right of the menu bar. Hold `⌘` and drag a ring to move it along the menu bar.

<br>

## Features

### Menu bar

For each limit the app draws a ring, a percentage, and the time to reset, in that order from left to right.

| What you see | Meaning |
|---|---|
| Letter inside the ring | The kind of limit. `S` is the session limit and is teal. `W` is the weekly limit across all models and is indigo. A model-scoped weekly limit uses the first letter of the model name; Fable is pink and other models are gray. |
| 16px ring | The usage of that limit. It fills clockwise from 12 o'clock and leaves the remaining share as a faint track. The filled arc uses the same color as the letter inside, switches to orange at 75%, and switches to red at 90%. |
| Percentage | Rounded usage. It turns orange at 75% and red at 90%. |
| Time next to it | Time until reset, abbreviated as `2d3h`, `4h12m`, or `45m`. |

Until the first response arrives after launch the app draws `C …`, and appends `?` when a fetch fails. Limits are fetched every 5 minutes and the remaining time is redrawn every minute.

### Menu

Clicking a ring in the menu bar opens the following menu.

- `계정: <email> (<plan>)` appears at the top. If the email cannot be read, the config directory name is shown instead.
- Each limit gets a line like `세션  42%  · 리셋까지 4h 12m`. A model-scoped weekly limit shows the model name in place of `주간`.
- The time of the last successful fetch appears as `갱신: 14:05`.
- When the last fetch failed, an `오류: ...` line appears as well.
- `지금 새로고침 ⌘R` fetches again immediately.
- `종료 ⌘Q` quits the app.

<br>

## Account selection

The app reads only the token of the account Claude Code uses, and never falls back to another account's token.

- When you pick a Claude account in the Orca app, it records that account's config directory in `~/Library/Application Support/orca/claude-profiles/selected-host`. If the file exists the app uses that directory. The keychain service is `Claude Code-credentials-<first 8 characters of the SHA-256 of the directory path>` and the email is read from `<directory>/.claude.json`.
- If the file does not exist or is empty the app uses the default account. Orca leaves the file empty when you pick the default account. The keychain service is `Claude Code-credentials` and the email is read from `~/.claude.json`.
- If the file exists but cannot be read, the app shows `계정 선택 파일 읽기 실패` (selection file unreadable) instead of falling back to the default account.
- If the selected account has no keychain entry, the app reports an error and does not look for another account's token.
- The app checks for an account switch every 60 seconds. When the account changes it clears the previous account's numbers and fetches again.

<br>

## Requirements

| Requirement | Notes |
|---|---|
| macOS 13 or later | This is an AppKit menu bar app. |
| Xcode Command Line Tools | The app builds with `swift build`. Install them with `xcode-select --install`, or install the Swift toolchain with `brew install swift`. |
| Claude Code sign-in | You need to be signed in with an account that has a Claude subscription to read the limits. |

<br>

## Uninstall

```sh
brew services stop lcalmsky/tidemark/tidemark
brew uninstall lcalmsky/tidemark/tidemark
brew untap lcalmsky/tidemark
```

Running the three lines in order stops the service and removes the app and the tap.

<br>

## Development

```sh
swift build
scripts/bundle.sh           # builds build/Tidemark.app
```

- **App icon** `swift scripts/make-icon.swift` regenerates `assets/AppIcon.icns`, and `scripts/bundle.sh` copies it into the bundle.
- **Release** `scripts/release.sh X.Y.Z -m "<summary of changed features>"` does the version, build, checks, tag, GitHub release, and Homebrew formula update in one go. If it stopped at the step that downloads the tarball, `scripts/release.sh --formula-only X.Y.Z` redoes only the formula update.

<br>

## Things to know

- The app uses `https://api.anthropic.com/api/oauth/usage`. The endpoint is undocumented and may change without notice. If the response format changes the app shows `?` or an `오류` line.
- The token is used only in the authorization header of requests to `api.anthropic.com`, and is never printed to the screen or to a log.

<br>

<p align="center"><a href="LICENSE">MIT</a></p>
