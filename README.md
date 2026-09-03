# Goobplayability release feed

This low-profile public repository is the pinned release source for the
Goobplayability client updater.

The updater is disabled by default. It accepts only `manifest.json` from this
repository, requires the exact supported Goober Dash build identifier, accepts
only the eight explicitly allowlisted script names, restricts every download
to this repository's `releases/<version>/` directory, and verifies declared
file size plus SHA-256 before installation.

Installation backs up every replaced file under the game's user-data directory
and writes rollback metadata. The previous scripts can be restored from
Goober Dash Settings → Client Tools → Roll Back.

Do not rewrite an existing release directory. Publish a new semantic version,
update the file sizes and hashes, and change `manifest.json` last.
