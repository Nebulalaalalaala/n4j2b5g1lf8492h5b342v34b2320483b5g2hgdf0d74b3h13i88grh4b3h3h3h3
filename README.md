# Goobplayability release feed

Pinned release source for the Goobplayability client updater.

The updater only reads `manifest.json` from this repository (schema 2). It
requires the exact supported Goober Dash build, only accepts mod-relative paths
with allowed file types, never touches Level Council files, restricts every
download to this repository's `releases/<version>/` folder, and checks each
file's size and SHA-256 before installing. Installs only receive files for the
tools they have (from `installed.json`).

Every replaced file is backed up first and can be restored from
Settings → Client Tools → Updates → Roll Back.

Releases carry code and data files; images, sounds and fonts come with the
installer. Don't rewrite an existing release folder: publish a new version,
and update `manifest.json` in the same commit.
