-- Per-album default view for the gallery's map filter (D35).
--
-- Stored as MapKit's own CoordinateRegion — a centre plus a span in degrees — rather than a zoom
-- level. MapKit JS has no integer zoom: `map.region` is the only thing you can read back after a
-- pan/drag and the only thing you can write to restore it, so saving is a straight copy in both
-- directions and no conversion can drift. Span doubles as the zoom: a small span is zoomed in.
--
-- All four columns move together. Any of them NULL means "no saved view" and the map falls back
-- to framing every pin, which is also what an album whose photos move around wants.
--
-- Degrees, WGS 84 — the same frame as file_metadata.gps_latitude/gps_longitude (V36).
ALTER TABLE albums
    ADD COLUMN map_center_lat DOUBLE NULL,
    ADD COLUMN map_center_lng DOUBLE NULL,
    ADD COLUMN map_span_lat DOUBLE NULL,
    ADD COLUMN map_span_lng DOUBLE NULL;
