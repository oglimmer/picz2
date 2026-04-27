/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.JobStatus;
import com.oglimmer.photoupload.entity.ProcessingJob;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface ProcessingJobRepository extends JpaRepository<ProcessingJob, Long> {

  /**
   * Atomic lease acquisition. Returns the next leaseable job id, skipping rows already locked by a
   * concurrent worker. MariaDB ≥ 10.6 is required for {@code SKIP LOCKED}.
   *
   * <p>A row is leaseable when it is QUEUED, or when it is PROCESSING but its lease has expired
   * (worker died). The dispatcher should call this inside a transaction and immediately update the
   * row before committing.
   */
  @Query(
      value =
          "SELECT id FROM processing_jobs "
              + "WHERE status = 'QUEUED' "
              + "   OR (status = 'PROCESSING' AND leased_until < NOW(6)) "
              + "ORDER BY created_at ASC "
              + "LIMIT 1 "
              + "FOR UPDATE SKIP LOCKED",
      nativeQuery = true)
  Optional<Long> findNextLeaseableId();

  @Modifying
  @Query(
      value =
          "UPDATE processing_jobs "
              + "SET status = 'PROCESSING', "
              + "    attempts = attempts + 1, "
              + "    leased_until = DATE_ADD(NOW(6), INTERVAL :leaseSeconds SECOND), "
              + "    leased_by = :workerId, "
              + "    started_at = COALESCE(started_at, NOW(6)) "
              + "WHERE id = :id",
      nativeQuery = true)
  int acquireLease(
      @Param("id") Long id,
      @Param("workerId") String workerId,
      @Param("leaseSeconds") int leaseSeconds);

  long countByStatus(JobStatus status);

  @Query("SELECT COUNT(j) FROM ProcessingJob j WHERE j.status IN :statuses")
  long countByStatusIn(@Param("statuses") List<JobStatus> statuses);

  /**
   * Single round-trip COUNT grouped by status. The metrics gauge and the backpressure filter both
   * read these values, so doing one query and caching the map is materially cheaper than six
   * separate {@code countByStatus} calls per refresh.
   */
  @Query("SELECT j.status, COUNT(j) FROM ProcessingJob j GROUP BY j.status")
  List<Object[]> countAllByStatusGrouped();

  List<ProcessingJob> findByStatusOrderByCreatedAtDesc(JobStatus status, Pageable pageable);
}
