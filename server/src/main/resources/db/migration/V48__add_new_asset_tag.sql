-- D70: which tag a newly registered asset gets, per user.
--
-- Since D68 every new asset got `all`, and `all` is what public visitors filter on — so a photo
-- taken on the phone reached a published album's share link within seconds, with no review step.
-- The tag is now a per-user choice between two system tags:
--   'hidden' — excluded from every public listing, so a new photo waits for the owner
--   'all'    — the D68 behaviour, visible the moment processing finishes
--
-- EVERY existing user is moved to 'hidden', not just new ones. The silent-publish window is the
-- thing being fixed; leaving current accounts on 'all' would leave it open for exactly the people
-- who already have published albums. Owners who want the old behaviour flip it in Profile.
ALTER TABLE users
  ADD COLUMN new_asset_tag VARCHAR(20) NOT NULL DEFAULT 'hidden';

-- `hidden` becomes a reserved system tag name. A user who already made an ordinary tag called
-- `hidden` would otherwise have it silently promoted, and their photos would drop out of the
-- public album. Rename theirs out of the way; `hidden-<tag id>` cannot collide with anything.
UPDATE tags SET name = CONCAT('hidden-', id) WHERE name = 'hidden';
