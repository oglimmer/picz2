/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.storage;

import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

/**
 * Everything needed to talk to one storage backend: the SDK clients, the bucket they address, and
 * the circuit breaker guarding them. Each backend gets its own breaker so an unreachable
 * user-supplied endpoint cannot fail calls to anyone else's storage.
 */
public record StorageClients(
    Long backendId,
    S3Client s3,
    S3Presigner presigner,
    String bucket,
    CircuitBreaker breaker,
    boolean systemDefault) {}
