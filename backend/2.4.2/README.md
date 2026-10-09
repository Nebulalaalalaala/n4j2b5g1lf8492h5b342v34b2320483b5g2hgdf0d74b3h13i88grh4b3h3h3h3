# Goober Hub moderation setup for 2.4.2

This folder is for the Supabase project owner. It is not installed by the client
updater. Publishing the client does not deploy this SQL automatically.

In the existing Supabase project's SQL Editor, run GOOBER_HUB_MODERATION.sql once,
after the current base GOOBER_HUB.sql. The migration is transactional and safe to
re-run. It preserves existing profiles, XP, install keys and Journey's private
admin passphrase. If base Hub SQL is ever re-run, run moderation LAST again.

Use Emilia's existing account, open Journey, press Ctrl+M, then open Reports &
moderation at the top. Use the same private passphrase as Journey Custom badges.
Do not paste that password, an install key, service key or game session in chat.
If Journey has never had a real admin passphrase configured, the server owner
must first configure journey_admin's id=1 pass_hash with a long private password's
SHA-256. No default password is installed or reset by this migration.

Reports retain message evidence. Bans restrict authenticated Goober Hub use;
mutes restrict Hub chat sending. They do NOT ban players from GooberDash or
public matches. Choose 1, 2 or 3 days, then confirm. Restrictions expire by server
time automatically. Historical reports without independently verified evidence
can only be dismissed. Anonymous public resources remain public.

Optional GOOBER_HUB_MODERATION_ROLLBACK.sql disables this moderation backend and
restores the captured prior claim/send implementations. It preserves XP,
accounts, report evidence and the action audit. Use only if intentionally rolling
back the server feature. Client updates can separately be rolled back from
Goobplayability Settings. Installer tiers are unchanged: these Hub helpers use
the existing social module.

Validated with isolated native UI and PostgreSQL-compatible tests, not a live
two-user moderation test. Test online with consenting test accounts after setup.
