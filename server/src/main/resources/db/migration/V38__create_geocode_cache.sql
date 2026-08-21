-- Reverse-geocoding cache: "what is the place name at this coordinate", as answered by the Apple
-- Maps Server API. Every gallery that groups photos by region asks for one name per region, and
-- the answer for a coordinate does not change — so the only sane number of times to ask Apple for
-- any given spot is once, per language, ever.
--
-- The cache is keyed on the *snapped* query point, latitude and longitude scaled by 10^4 (~11 m at
-- the equator) and stored as INT so the lookup is an integer index probe rather than a float
-- comparison. ±90/±180 degrees scaled by 10^4 fit comfortably in INT.
--
-- Lookups are not limited to an exact key match: ReverseGeocodeService first scans the box around
-- the query for any cached point within its reuse radius (a few hundred metres, configurable) and
-- takes the nearest hit, because two photo clusters in the same village must not cost two calls to
-- Apple. idx_geocode_cache_point serves both the exact probe and that range scan.
--
-- place_name NULL is a real, deliberate answer: "asked Apple, it had nothing to say about this
-- spot" (mid-ocean, Antarctica). Those rows are re-checked after maps.geocode.negative-ttl-days
-- and stop the same empty coordinate being asked on every page load in between.
CREATE TABLE geocode_cache (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    -- Snapped query point, degrees * 10000, WGS 84 — same reference frame as file_metadata.gps_*.
    lat_e4 INT NOT NULL,
    lng_e4 INT NOT NULL,
    -- Language the name was resolved in, as the short tag we asked Apple for ("en", "de").
    -- Names are localised, so the same point genuinely has one row per language.
    language VARCHAR(16) NOT NULL,
    -- The label the UI shows. NULL = negative cache entry, see above.
    place_name VARCHAR(255) NULL,
    -- The components behind that label, kept so the label rule can be changed later without
    -- re-asking Apple for every coordinate we already know.
    locality VARCHAR(255) NULL,
    sub_locality VARCHAR(255) NULL,
    administrative_area VARCHAR(255) NULL,
    country VARCHAR(255) NULL,
    country_code VARCHAR(8) NULL,
    resolved_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Cheap popularity signal for pruning later; not read by any query today.
    hit_count BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT uk_geocode_cache_point UNIQUE (lat_e4, lng_e4, language),
    INDEX idx_geocode_cache_point (language, lat_e4, lng_e4)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
