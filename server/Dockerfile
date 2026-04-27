FROM eclipse-temurin:latest AS builder

WORKDIR /app/server

# layer 1 - cache all dependencies, update only if pom.xml or maven-wrapper.properties changes
COPY server/.mvn/wrapper/maven-wrapper.properties ./.mvn/wrapper/
COPY server/mvnw server/pom.xml ./

# Make mvnw executable
RUN chmod +x ./mvnw

# Pre-download dependencies and plugins, cache Maven directory
RUN --mount=type=cache,target=/root/.m2 ./mvnw --no-transfer-progress dependency:go-offline

# layer 2 - build if any file changed
COPY server/src ./src

# we need to copy the .git directory to get the commit hash
WORKDIR /app
COPY .git/ .git/

WORKDIR /app/server
RUN --mount=type=cache,target=/root/.m2 ./mvnw --no-transfer-progress clean package -DskipTests

FROM eclipse-temurin:latest

WORKDIR /app

# Build ImageMagick from source with latest libheif for better HEIC support
RUN apt-get update && \
    # Install build dependencies
    apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        pkg-config \
        wget \
        ca-certificates \
        git \
        # ImageMagick dependencies
        libjpeg-dev \
        libpng-dev \
        libtiff-dev \
        libwebp-dev \
        libfreetype6-dev \
        libfontconfig1-dev \
        # HEIC codec build dependencies
        libde265-dev \
        libaom-dev \
        libx265-dev && \
    # Make /usr/local/lib win lookups against /usr/lib/<triplet>/. ffmpeg + libvips-tools
    # (installed below) drag in Ubuntu's libheif1 1.17.x as a transitive dep, which
    # lacks heif_has_compatible_filetype and applies stricter aux-image / metadata
    # checks than 1.18 — both of which break HEIC decode for modern iOS files. Without
    # this entry, ld.so.cache resolves SONAME libheif.so.1 to the apt copy and shadows
    # the /usr/local/lib build done in the next step.
    echo "/usr/local/lib" > /etc/ld.so.conf.d/00-photoupload-local.conf && \
    # Build and install libheif (latest version for modern HEIC support)
    cd /tmp && \
    wget https://github.com/strukturag/libheif/releases/download/v1.18.2/libheif-1.18.2.tar.gz && \
    tar xzf libheif-1.18.2.tar.gz && \
    cd libheif-1.18.2 && \
    mkdir build && cd build && \
    # WITH_EXAMPLES installs heif-convert into /usr/local/bin — that is the canonical
    # HEIC → JPEG path; ImageMagick's HEIC reader is now a fallback only.
    # CMAKE_INSTALL_RPATH bakes /usr/local/lib into heif-convert's RPATH so it always
    # picks up the matching libheif.so.1 even if a different copy lands on the global
    # search path later.
    cmake --preset=release -DWITH_EXAMPLES=ON \
          -DCMAKE_INSTALL_RPATH=/usr/local/lib \
          -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    test -x /usr/local/bin/heif-convert && \
    # Build and install ImageMagick (latest version)
    cd /tmp && \
    wget https://github.com/ImageMagick/ImageMagick/archive/refs/tags/7.1.1-39.tar.gz && \
    tar xzf 7.1.1-39.tar.gz && \
    cd ImageMagick-7.1.1-39 && \
    ./configure \
        --prefix=/usr/local \
        --with-heic=yes \
        --with-jpeg=yes \
        --with-png=yes \
        --with-tiff=yes \
        --with-webp=yes \
        --disable-static \
        --enable-shared && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    # Explicitly install ALL runtime libraries before purging -dev packages
    # This ensures apt knows these are explicitly wanted and won't remove them
    apt-get install -y --no-install-recommends \
        ffmpeg \
        libvips-tools \
        libjpeg-turbo8 \
        libjpeg8 \
        libpng16-16 \
        libtiff6 \
        libwebp7 \
        libwebpdemux2 \
        libwebpmux3 \
        libfreetype6 \
        libfontconfig1 \
        libde265-0 \
        libaom3 \
        libx265-199 \
        libbrotli1 \
        libbz2-1.0 \
        libdeflate0 \
        libexpat1 \
        zlib1g \
        uuid-runtime \
        liblerc4 \
        libsharpyuv0 \
        libjbig0 \
        liblzma5 \
        libzstd1 && \
    # Re-cache library paths now that runtime debs (which can ship their own libheif1)
    # have been laid down. /usr/local/lib stays first thanks to the conf.d entry above.
    ldconfig && \
    # Hard-fail the image build if libheif.so.1 ever resolves to the apt copy. Pinning
    # this here is cheap insurance against a future Dockerfile reorder that breaks
    # HEIC decode silently at runtime.
    ldd /usr/local/bin/heif-convert | grep 'libheif\.so' \
        | grep -q '=> /usr/local/lib/' \
        || (echo "heif-convert is not linked against /usr/local/lib/libheif" >&2; \
            ldd /usr/local/bin/heif-convert >&2; exit 1) && \
    # Clean up build artifacts and BUILD dependencies only (keep runtime libs!)
    cd / && \
    rm -rf /tmp/* && \
    apt-get purge -y \
        build-essential \
        cmake \
        cmake-data \
        pkg-config \
        wget \
        ca-certificates \
        git \
        git-man \
        # Remove only -dev packages, keep runtime libraries
        libjpeg-dev \
        libjpeg-turbo8-dev \
        libjpeg8-dev \
        libpng-dev \
        libtiff-dev \
        libwebp-dev \
        libfreetype-dev \
        libfontconfig-dev \
        libfontconfig1-dev \
        libde265-dev \
        libaom-dev \
        libx265-dev \
        libbrotli-dev \
        libbz2-dev \
        libdeflate-dev \
        libexpat1-dev \
        zlib1g-dev \
        uuid-dev \
        liblerc-dev \
        libsharpyuv-dev \
        libjbig-dev \
        liblzma-dev \
        libzstd-dev \
        # Remove compiler toolchain
        gcc \
        gcc-13 \
        gcc-13-base \
        gcc-13-aarch64-linux-gnu \
        gcc-aarch64-linux-gnu \
        g++ \
        g++-13 \
        g++-13-aarch64-linux-gnu \
        g++-aarch64-linux-gnu \
        cpp \
        cpp-13 \
        cpp-13-aarch64-linux-gnu \
        cpp-aarch64-linux-gnu \
        libgcc-13-dev \
        libstdc++-13-dev \
        libc6-dev \
        libc-dev-bin \
        linux-libc-dev \
        libcrypt-dev \
        # Remove build tools
        make \
        patch \
        dpkg-dev \
        libdpkg-perl && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG APP_USER=appuser
ARG APP_UID=10001
ARG APP_GID=10001

RUN groupadd  -g "${APP_GID}" "${APP_USER}" \
     && useradd   -m -u "${APP_UID}" -g "${APP_GID}" "${APP_USER}"

COPY --chown=${APP_USER}:${APP_USER} --from=builder /app/server/target/photo-upload-server-*.jar app.jar

EXPOSE 8080

USER ${APP_USER}

CMD ["java", "-jar", "app.jar"]
