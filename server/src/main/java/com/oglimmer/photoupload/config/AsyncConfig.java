/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import com.oglimmer.photoupload.config.Profiles;
import org.springframework.context.annotation.Profile;

import java.util.concurrent.ThreadPoolExecutor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

@Profile(Profiles.API)
@Configuration
@EnableAsync
@Slf4j
public class AsyncConfig {

  public static final String FILE_PROCESSING_EXECUTOR = "fileProcessingExecutor";

  @Bean(name = FILE_PROCESSING_EXECUTOR)
  public ThreadPoolTaskExecutor fileProcessingExecutor(FileStorageProperties properties) {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(properties.getMaxConcurrentProcessing());
    executor.setMaxPoolSize(properties.getMaxConcurrentProcessing());
    executor.setQueueCapacity(properties.getProcessingQueueCapacity());
    executor.setThreadNamePrefix("file-proc-");
    executor.setRejectedExecutionHandler(new ThreadPoolExecutor.AbortPolicy());
    executor.setWaitForTasksToCompleteOnShutdown(true);
    executor.setAwaitTerminationSeconds(300);
    executor.initialize();
    log.info(
        "File processing executor initialized: pool={}, queue={}",
        properties.getMaxConcurrentProcessing(),
        properties.getProcessingQueueCapacity());
    return executor;
  }
}
