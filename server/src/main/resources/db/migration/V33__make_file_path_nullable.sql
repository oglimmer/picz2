-- Phase 6 / Gap 4-finish: the retention CronJob purges originals from MinIO once their derivatives
-- are durable and the row is older than `retention.original-days`. After purge, file_metadata.file_path
-- is set to NULL — the row is still served from its thumb/medium/large derivatives. Drop the
-- NOT NULL constraint so the runner can null the column without violating schema.
ALTER TABLE file_metadata
  MODIFY COLUMN file_path VARCHAR(512) NULL;
