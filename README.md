# Goobplayability release feed

Pinned release source for the Goobplayability client updater.

## Goobplayability 4.0

Open F1 → Settings → General → Interface & updates to check for and install the
update. Restart Goober Dash after installation. The interactive notes are in
F1 → News.

4.0 adds the Galaxy workspace, Sections and run recovery, expanded Overlay and
Effects Studios, Avatar Studio improvements, Zoom, spectator controls and
Journey progress and rewards. Existing installer tiers determine access to TAS
and the other optional tools.

4.0.1 opens online Workshop for supported creations and adds opt-in sharing
of worn custom effects with other updated Goobplayability clients.

Clip recording and Windows media sessions use the separate
[Windows components](components/4.0.0/README.md). MP4 recording and the local
MP3 decoder also require FFmpeg.

The updater only reads `manifest.json` from this repository (schema 2). It
requires the exact supported Goober Dash build, only accepts mod-relative paths
with allowed file types, never touches Level Council files, restricts every
download to this repository's `releases/<version>/` folder, and checks each
file's size and SHA-256 before installing. Installs only receive files for the
tools they have (from `installed.json`).

Every replaced file is backed up first and can be restored from
Settings → Interface & updates → Roll back last update.

Releases carry code and data, map thumbnails and explicitly registered new
assets. Other images, sounds and fonts come with the installer.

In 2.4.0, Goober Hub is delivered with the existing `social` module (Friends &
Party). Basic installs receive everyday tools; Macro Bot/TAS, overlays, Replay
Library and Infinite Dash remain Advanced selections. Existing Developer tools
are carried forward unchanged. Installer executables are not part of this feed.

Published release folders are immutable. The preceding release remains available
so an update already in progress can finish against its original manifest.
