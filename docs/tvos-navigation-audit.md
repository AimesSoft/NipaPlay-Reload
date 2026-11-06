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
- Content focus is restored only to a currently attached, traversable control.
  When login replaces its prompt with results, reopening/closing navigation
  chooses an actual content action instead of a detached node or scroll scope.
- WebDAV/SMB form actions and password-visibility buttons show a visible focus
  border and background instead of silently suppressing focus feedback.
- Debug builds remove any stale AOT App.framework left by a preceding Release
  build, so simulator checks execute the current Dart kernel.

## Evidence and limits

| Area | Automated coverage | Simulator observation |
| --- | --- | --- |
| Login and detail failure | Select opens login; retry invokes loader; shared library survives metadata failure | Native username and secure password editing, completion/cancellation; existing review account logged in inside the app; home rankings recovered; login survived restart; authenticated details loaded and episode 12 was reached |
| Main navigation | Hidden panels excluded; content focus restored; Tab/Right target the highlighted row | Home, Video Player, Media Library and Account reached with Menu, arrows and Right; content focus visibly restored after returning |
| Settings | Category/content traversal, left return, close and focus restoration | All 11 categories reached; Right entered content, arrows traversed actions/sliders, Left returned to categories (sliders retain horizontal adjustment); About reached with its update action focused |
| Playback | Player controls, menu/content traversal, switches, sliders and remote input | Generated HTTP test video played and paused; all 11 menu categories reached; final build returned from playback to Media Library with focus on its header action |
| Playlist | HTTP/HTTPS do not read a local directory or display URL tokens | Final build showed tv.mp4 as the current network stream with host-only subtitle and no local-directory error |
| Media libraries | Media-server detail focus and shared-library metadata fallback | Media Library remote/add-media controls and all six source choices reached; NipaPlay client picker opened; Jellyfin, Emby and Dandanplay connection buttons reached; WebDAV cancel/test/add and SMB cancel/save reached with visible focus, SMB scrolled to its final fields; authenticated server/file browsing still needs service-specific data |
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

## Network diagnosis and final verification

The local network's direct HTTPS route returned an expired `pan-fw-trust`
certificate chain. The Mac's configured HTTP CONNECT proxy returned the valid
Let's Encrypt YR2 chain. A diagnostic request inside the simulator confirmed the
same interception; setting launch-process proxy variables did not configure
Dart's tvOS environment. Using the existing app HTTP-proxy setting in this test
simulator restored normal certificate-validated HTTPS and the in-app review
account login succeeded. No certificate exceptions, HTTP credential fallback or
TLS bypass were added. This local finding does not establish the cause of
Apple's earlier rejection.

The final focus recovery regression suite passed 21 cases. CI for code commit
`f5a89e0c2` passed Analyze and Test and Build tvOS package. Simulator manual
observations above were repeated after removing the stale AOT framework.
App Store build 1.11.11 (1104.2) was generated from that commit, passed strict
nested signature verification and Apple's archive validation, and includes the
five expected privacy declarations. The app-icon catalog remains identical to
the previously corrected main assets. Physical-device Siri Remote gestures and
authenticated third-party server combinations remain outside this simulator
verification.

A final form pass found suppressed focus feedback on standard WebDAV/SMB
buttons. After adding focused borders/backgrounds, the simulator showed visible
selection for cancel, test, add/save, and long SMB forms scrolled to their final
controls. The existing text-input/server-dialog regression run passed 15 cases.
These changes supersede build 1104.2; replacement build 1104.3 is being prepared.
