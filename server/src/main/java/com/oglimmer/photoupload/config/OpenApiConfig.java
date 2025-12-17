/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OpenApiConfig {

  @Bean
  public OpenAPI photoUploadOpenAPI() {
    final String securitySchemeName = "basicAuth";

    return new OpenAPI()
        .info(
            new Info()
                .title("Photo Upload API")
                .description(
                    "API for managing photo and video uploads with albums, tags, and slideshow recordings")
                .version("1.0.0")
                .contact(new Contact().name("Photo Upload Team").email("oglimmer@gmail.com"))
                .license(
                    new License()
                        .name("Apache 2.0")
                        .url("https://www.apache.org/licenses/LICENSE-2.0.html")))
        .components(
            new Components()
                .addSecuritySchemes(
                    securitySchemeName,
                    new SecurityScheme()
                        .type(SecurityScheme.Type.HTTP)
                        .scheme("basic")
                        .description("HTTP Basic Authentication")))
        .addSecurityItem(new SecurityRequirement().addList(securitySchemeName));
  }
}
