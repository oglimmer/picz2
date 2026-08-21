-- Which version of the label rule produced a cached name.
--
-- The first release read Apple's *flat* place fields, but the Maps Server API nests locality and
-- administrativeArea inside structuredAddress — so only `country` ever matched and every region in
-- a country was labelled after the country ("Canada" for a whole trip). Those rows are cached and
-- correct-looking, so nothing would ever re-ask for them.
--
-- Hence a version stamp rather than a TRUNCATE: rows below ReverseGeocodeService.LABEL_VERSION are
-- treated as stale and re-resolved the next time somebody looks at that spot, spread over normal
-- browsing instead of a thundering herd, and the same mechanism handles the next rule change.
-- Existing rows default to 0, which is below every real version.
ALTER TABLE geocode_cache
    ADD COLUMN resolver_version INT NOT NULL DEFAULT 0;
