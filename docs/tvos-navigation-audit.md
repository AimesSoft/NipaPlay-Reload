# tvOS navigation audit — 2026-11-04

This audit follows the tvOS 1.11.11 (1102.1) rejection under 2.1(a).
Apple's screenshots showed an unauthenticated Dandanplay detail request and a
home page requiring login. They do not establish that the account password was
incorrect. The existing review account successfully authenticated against the
official HTTPS gateway during this audit; no credentials or tokens are recorded
here.

## Fixes

- Unauthenticated details and rankings offer a focusable login action. Successful
  login resumes loading; local and shared-library files remain available without
  a Dandanplay account.
- The detail error screen delegates Select to its visible retry/return buttons.
  Deferred focus requests no longer steal focus from a covering dialog.
- Hidden navigation, settings and playback surfaces cannot receive focus.
  Closing panels restores the originating content control. Tab and Right follow
  the highlighted navigation row; playback context follows the page ID.
- Focused actions scroll into view. Repeated activation/back events are ignored.
- tvOS uses a UIKit keyboard with secure password entry, completion/cancellation
  and focus restoration. Phone QR input remains available as an alternative.
- Returning to the media library exits playback and selects that page. Standalone
  HTTP/HTTPS playlists show the current stream instead of enumerating a local
  directory.
- Apple TV local files use writable Caches instead of read-only Documents.
- An Xcode phase embeds upstream privacy declarations for SPM and CocoaPods,
  including sqflite_tvos inside its framework. Statically linked plugins retain
  their declarations in resource bundles.

## Evidence and limits

| Area | Automated coverage | Simulator observation |
| --- | --- | --- |
| Login and detail failure | Select opens login; retry invokes loader; shared library survives metadata failure | Native username entry and return to password field; secure editor and cancellation |
| Main navigation | Hidden panels excluded; content focus restored; Tab/Right target the highlighted row | Home and Video Player reached with Menu, arrows and Right |
| Settings | Category/content traversal, left return, close and focus restoration | Further manual walk-through pending |
| Playback | Player controls, menu/content traversal, switches, sliders and remote input | Generated HTTP test video played and paused; all 11 menu categories reached; common action entered and playback exited |
| Playlist | HTTP/HTTPS do not read a local directory or display URL tokens | Original stream-directory error reproduced; corrected branch covered by widget tests |
| Media libraries | Media-server detail focus and shared-library metadata fallback | Media Library page and its remote/add-media controls reached; authenticated server/file browsing still needs service-specific data |
| Storage | Writable directory and reopening files without Documents | Physical-device restriction addressed from plugin diagnostics; physical hardware not available |

The first focused run passed 88 cases; tvOS policy checks passed 7 cases. The
later playlist/input/player regression run passed 29 cases. Initial PR CI passed
both Analyze and Test and the tvOS simulator build. Local full-suite execution
encountered two UDP tests unable to bind port 32123 because a separate running
NipaPlay instance owned it; that app was left running. CI runs in isolation.

Manual observations used Apple TV 4K (3rd generation), tvOS 26.0 Simulator and a
connected hardware keyboard. Apple reviewed on tvOS 26.6.1 physical hardware.
Simulator success does not establish hardware Siri Remote gesture behavior or
complete interoperability with every Emby/Jellyfin/SMB/WebDAV server.

The App Store build uses `NIPAPLAY_APP_STORE=true`; GitHub distributions retain
their existing sponsorship policy. Submission additionally requires archive
signature, icon and privacy-manifest verification.
