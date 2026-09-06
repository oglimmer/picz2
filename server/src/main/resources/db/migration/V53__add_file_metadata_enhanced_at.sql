-- D83: remember that an asset has been auto-enhanced.
--
-- ENHANCE (D81) rewrites the original in place and keeps no copy of the previous bytes, so a
-- second run compounds on the first: contrast on top of contrast, saturation on top of
-- saturation. Nothing on the row said it had already happened, so neither client could warn and
-- a bulk enhance over a whole album re-cooked everything it had cooked before.
--
-- One nullable timestamp: null means "never enhanced", a value means "enhanced then". The worker
-- stamps it in the same short TX that commits the rewrite, so it can never claim an enhance that
-- did not land. Not a boolean because the date is worth showing in a tooltip and costs nothing.
--
-- No backfill on purpose: assets enhanced before this migration stay null and read as
-- un-enhanced. There is no record of which those were, and guessing would be worse than the
-- honest "we do not know" — the same reasoning as the D79 tag state.
ALTER TABLE file_metadata
    ADD COLUMN enhanced_at TIMESTAMP(6) NULL;
