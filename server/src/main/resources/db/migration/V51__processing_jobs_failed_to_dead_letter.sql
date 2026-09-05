-- D76: retire the FAILED job status.
--
-- A failed attempt is re-queued (status back to QUEUED) until max_attempts, then DEAD_LETTER.
-- FAILED was written by an older dispatcher and never read back: findNextLeaseableId only leases
-- QUEUED rows and the dead-letter listing only shows DEAD_LETTER, so a FAILED row sat invisible
-- and unretried for good. Every such row is by now exactly what DEAD_LETTER means — an operator
-- has to look at it — so it is renamed rather than deleted, and the enum constant goes.
UPDATE processing_jobs SET status = 'DEAD_LETTER' WHERE status = 'FAILED';
