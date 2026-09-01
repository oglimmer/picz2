#!/usr/bin/env python3
"""One-way migration: picz (v1) -> picz2 / photo-upload (v2), one user at a time.

What it moves
  * the v1 user's albums (album.description -> v2 albums.name)
  * IMAGE elements only
  * the resized JPEG/PNG v1 keeps in AWS S3 under images/<filename> becomes the v2
    "original" at MinIO originals/<stored_filename>
  * capture date and GPS, taken from the v1 DB (see "Why two phases")

What it does NOT move
  * SECTION (182) and MAP (68) elements -- v2 has no equivalent element type
  * per-image captions (album_element.description) -- v2 file_metadata has no caption column
  * v1 small/ renditions -- the v2 worker regenerates thumb/medium/large from the original

Why two phases
  v1 strips EXIF from what it stores (ImageResizeService.removeExif), so the v2 PROCESS job
  finds no capture date and no GPS in the bytes -- and it overwrites gps_* with NULL when it
  runs. Date and GPS carried over from the v1 DB must therefore land AFTER processing:

    phase upload    create albums, PUT objects, insert QUEUED rows + PROCESS jobs
    phase finalize  once those rows are DONE, write exif_date_time_original / gps_* from v1

  Timezones need no correction: the v1 api pod runs in UTC, so metadata-extractor's
  getDateOriginal() stored the camera's wall clock as a naive UTC datetime. Writing it
  straight through with capture_utc_offset_seconds = 0 keeps v2's "group by day" correct.

Idempotency
  Every migrated row carries content_id = 'piczv1:<v1 album_element.id>'. A re-run skips what
  already exists, so an interrupted run simply continues where it stopped.
"""

import argparse
import hashlib
import mimetypes
import os
import secrets
import sys
import time
import uuid

import boto3
import pymysql
from botocore.config import Config
from botocore.exceptions import ClientError

MARKER = "piczv1:"
NO_TAG = "no_tag"
ORIGINALS_PREFIX = "originals/"
SYSTEM_STORAGE_BACKEND_ID = 1

EXT_MIME = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png"}


def env(name, default=None, required=False):
    value = os.environ.get(name, default)
    if required and not value:
        sys.exit(f"missing required env var {name}")
    return value


def connect(prefix):
    """Open a MariaDB connection from the {prefix}_DB_* env vars, pinned to UTC."""
    conn = pymysql.connect(
        host=env(f"{prefix}_DB_HOST", required=True),
        port=int(env(f"{prefix}_DB_PORT", "3306")),
        user=env(f"{prefix}_DB_USER", required=True),
        password=env(f"{prefix}_DB_PASSWORD", required=True),
        database=env(f"{prefix}_DB_NAME", required=True),
        charset="utf8mb4",
        autocommit=False,
        cursorclass=pymysql.cursors.DictCursor,
    )
    with conn.cursor() as cur:
        cur.execute("SET time_zone = '+00:00'")
    conn.commit()
    return conn


def s3_source():
    return boto3.client(
        "s3",
        region_name=env("V1_S3_REGION", "eu-central-1"),
        aws_access_key_id=env("AWS_ACCESS_KEY_ID", required=True),
        aws_secret_access_key=env("AWS_SECRET_ACCESS_KEY", required=True),
    )


def s3_target():
    return boto3.client(
        "s3",
        endpoint_url=env("V2_S3_ENDPOINT", required=True),
        region_name=env("V2_S3_REGION", "us-east-1"),
        aws_access_key_id=env("V2_S3_ACCESS_KEY", required=True),
        aws_secret_access_key=env("V2_S3_SECRET_KEY", required=True),
        config=Config(s3={"addressing_style": "path"}, signature_version="s3v4"),
    )


def extension_of(filename):
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "jpg"
    return ext if ext.isalnum() else "jpg"


def mime_of(ext):
    return EXT_MIME.get(ext) or mimetypes.types_map.get("." + ext) or "image/jpeg"


def stored_filename_for(v1_filename):
    """Mirror FileStorageService: <base>-<epoch_ms>-<9 hex>.<ext>, unique per call."""
    ext = extension_of(v1_filename)
    base = v1_filename.rsplit(".", 1)[0] if "." in v1_filename else v1_filename
    suffix = f"{int(time.time() * 1000)}-{uuid.uuid4().hex[:9]}"
    return f"{base}-{suffix}.{ext}", ext


def hex_token(nbytes):
    return secrets.token_hex(nbytes)


# --------------------------------------------------------------------------- lookups


def v2_user_id(v2, email):
    with v2.cursor() as cur:
        cur.execute("SELECT id FROM users WHERE email = %s", (email,))
        row = cur.fetchone()
    if not row:
        sys.exit(f"no v2 user with email {email!r} -- create the account first")
    return row["id"]


def v1_user_ids(v1, email):
    with v1.cursor() as cur:
        cur.execute("SELECT id FROM user WHERE email = %s ORDER BY id", (email,))
        ids = [r["id"] for r in cur.fetchall()]
    if not ids:
        sys.exit(f"no v1 user with email {email!r}")
    return ids


def ensure_no_tag(v2, user_id, dry_run):
    with v2.cursor() as cur:
        cur.execute(
            "SELECT id FROM tags WHERE user_id = %s AND name = %s", (user_id, NO_TAG)
        )
        row = cur.fetchone()
        if row:
            return row["id"]
        if dry_run:
            return None
        cur.execute(
            "INSERT INTO tags (user_id, name, created_at) VALUES (%s, %s, UTC_TIMESTAMP(6))",
            (user_id, NO_TAG),
        )
        tag_id = cur.lastrowid
    v2.commit()
    print(f"  created '{NO_TAG}' tag id={tag_id} for user {user_id}")
    return tag_id


def album_name_for(v1_album):
    return (v1_album["description"] or "").strip() or f"picz-{v1_album['id']}"


def find_or_create_album(v2, user_id, name, v1_album, publish, dry_run):
    """Return (v2_album_id, created). Matched by (user_id, name), which is v2's unique key."""
    with v2.cursor() as cur:
        cur.execute(
            "SELECT id FROM albums WHERE user_id = %s AND name = %s", (user_id, name)
        )
        row = cur.fetchone()
        if row:
            return row["id"], False
        if dry_run:
            return None, True
        cur.execute(
            "SELECT COALESCE(MAX(display_order), -1) + 1 AS nxt FROM albums WHERE user_id = %s",
            (user_id,),
        )
        display_order = cur.fetchone()["nxt"]
        cur.execute(
            """INSERT INTO albums
                 (user_id, storage_backend_id, name, description, created_at, updated_at,
                  display_order, share_token, analytics_paused, published, published_at)
               VALUES (%s, %s, %s, NULL, %s, UTC_TIMESTAMP(), %s, %s, 0, %s, %s)""",
            (
                user_id,
                SYSTEM_STORAGE_BACKEND_ID,
                name,
                v1_album["creation_date"],
                display_order,
                hex_token(32),
                1 if publish else 0,
                v1_album["creation_date"] if publish else None,
            ),
        )
        album_id = cur.lastrowid
    v2.commit()
    return album_id, True


# --------------------------------------------------------------------------- phases


def phase_upload(args, v1, v2, src, dst):
    v2_uid = v2_user_id(v2, args.email)
    v1_uids = v1_user_ids(v1, args.email)
    print(f"v1 user ids {v1_uids} -> v2 user id {v2_uid}")

    no_tag_id = ensure_no_tag(v2, v2_uid, args.dry_run)

    with v1.cursor() as cur:
        cur.execute(
            "SELECT id, description, creation_date FROM album "
            f"WHERE user_id IN ({','.join(['%s'] * len(v1_uids))}) ORDER BY id",
            v1_uids,
        )
        albums = cur.fetchall()

    src_bucket = env("V1_S3_BUCKET", required=True)
    src_prefix = env("V1_S3_PREFIX", "images/")
    dst_bucket = env("V2_S3_BUCKET", required=True)

    totals = {"albums": 0, "uploaded": 0, "skipped": 0, "missing": 0}

    for album in albums:
        with v1.cursor() as cur:
            cur.execute(
                """SELECT id, filename, order_no, creation_date, entry_creation_date,
                          latitude, longitude
                   FROM album_element
                   WHERE album_id = %s AND element_type = 'IMAGE'
                     AND filename IS NOT NULL AND filename <> ''
                   ORDER BY order_no, id""",
                (album["id"],),
            )
            elements = cur.fetchall()

        if not elements and not args.include_empty_albums:
            print(f"- skip empty v1 album {album['id']} {album_name_for(album)!r}")
            continue

        name = album_name_for(album)
        album_id, created = find_or_create_album(
            v2, v2_uid, name, album, args.publish, args.dry_run
        )
        totals["albums"] += 1
        print(
            f"* album {name!r} v1={album['id']} v2={album_id} "
            f"({'created' if created else 'exists'}) {len(elements)} images"
        )

        for index, element in enumerate(elements):
            content_id = MARKER + str(element["id"])
            with v2.cursor() as cur:
                cur.execute(
                    "SELECT id FROM file_metadata WHERE content_id = %s", (content_id,)
                )
                if cur.fetchone():
                    totals["skipped"] += 1
                    continue

            if args.limit and totals["uploaded"] >= args.limit:
                print(f"  reached --limit {args.limit}, stopping")
                summarise(totals)
                return

            key = src_prefix + element["filename"]
            if args.dry_run:
                print(f"  would copy s3://{src_bucket}/{key}")
                totals["uploaded"] += 1
                continue

            try:
                body = src.get_object(Bucket=src_bucket, Key=key)["Body"].read()
            except ClientError as exc:
                code = exc.response.get("Error", {}).get("Code")
                if code in ("NoSuchKey", "404"):
                    print(f"  !! missing in v1 S3: {key} (element {element['id']})")
                    totals["missing"] += 1
                    continue
                raise

            stored, ext = stored_filename_for(element["filename"])
            mime = mime_of(ext)
            checksum = hashlib.sha256(body).hexdigest()
            storage_key = ORIGINALS_PREFIX + stored

            dst.put_object(
                Bucket=dst_bucket, Key=storage_key, Body=body, ContentType=mime
            )

            with v2.cursor() as cur:
                cur.execute(
                    """INSERT INTO file_metadata
                         (original_name, stored_filename, file_size, mime_type, file_path,
                          uploaded_at, checksum, content_id, album_id, display_order,
                          public_token, rotation, derivative_bytes,
                          processing_status, processing_attempts)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 0, 0, 'QUEUED', 0)""",
                    (
                        element["filename"],
                        stored,
                        len(body),
                        mime,
                        storage_key,
                        element["entry_creation_date"],
                        checksum,
                        content_id,
                        album_id,
                        index,
                        hex_token(24),
                    ),
                )
                asset_id = cur.lastrowid
                cur.execute(
                    "INSERT INTO image_tags (file_metadata_id, tag_id, tagged_at) "
                    "VALUES (%s, %s, UTC_TIMESTAMP(6))",
                    (asset_id, no_tag_id),
                )
                cur.execute(
                    """INSERT INTO processing_jobs
                         (asset_id, job_type, status, attempts, max_attempts, created_at)
                       VALUES (%s, 'PROCESS', 'QUEUED', 0, 3, UTC_TIMESTAMP(6))""",
                    (asset_id,),
                )
            # One commit per image: an interrupted run loses at most this one asset.
            v2.commit()
            totals["uploaded"] += 1
            if totals["uploaded"] % 50 == 0:
                print(f"  ... {totals['uploaded']} uploaded")

    summarise(totals)


def phase_finalize(args, v1, v2):
    """Write v1 capture date + GPS onto rows the worker has finished.

    Must run after PROCESS: that job sets gps_* from the (EXIF-free) bytes and would
    otherwise wipe whatever we wrote here.
    """
    with v2.cursor() as cur:
        cur.execute(
            """SELECT f.id, f.content_id, f.processing_status
               FROM file_metadata f
               JOIN albums a ON a.id = f.album_id
               JOIN users u ON u.id = a.user_id
               WHERE u.email = %s AND f.content_id LIKE %s""",
            (args.email, MARKER + "%"),
        )
        rows = cur.fetchall()

    done = [r for r in rows if r["processing_status"] == "DONE"]
    pending = len(rows) - len(done)
    print(f"{len(rows)} migrated rows, {len(done)} DONE, {pending} still processing")
    if pending and not args.force:
        print("re-run once processing has finished, or pass --force to do the DONE ones now")
        if not done:
            return

    updated = 0
    for row in done:
        element_id = int(row["content_id"][len(MARKER):])
        with v1.cursor() as cur:
            cur.execute(
                "SELECT creation_date, latitude, longitude FROM album_element WHERE id = %s",
                (element_id,),
            )
            element = cur.fetchone()
        if not element:
            continue

        has_gps = element["latitude"] is not None and element["longitude"] is not None
        if args.dry_run:
            updated += 1
            continue
        with v2.cursor() as cur:
            cur.execute(
                """UPDATE file_metadata
                     SET exif_date_time_original = %s,
                         exif_date_source = %s,
                         capture_utc_offset_seconds = %s,
                         gps_latitude = %s,
                         gps_longitude = %s,
                         gps_source = %s
                   WHERE id = %s""",
                (
                    element["creation_date"],
                    "EXIF_FALLBACK_ZONE" if element["creation_date"] else "NONE",
                    0 if element["creation_date"] else None,
                    element["latitude"] if has_gps else None,
                    element["longitude"] if has_gps else None,
                    "EXIF_GPS" if has_gps else "NONE",
                    row["id"],
                ),
            )
        v2.commit()
        updated += 1
    print(f"backfilled date/GPS on {updated} rows")


def phase_status(args, v1, v2):
    with v2.cursor() as cur:
        cur.execute(
            """SELECT f.processing_status AS s, COUNT(*) AS c
               FROM file_metadata f
               JOIN albums a ON a.id = f.album_id
               JOIN users u ON u.id = a.user_id
               WHERE u.email = %s AND f.content_id LIKE %s
               GROUP BY f.processing_status""",
            (args.email, MARKER + "%"),
        )
        for row in cur.fetchall():
            print(f"{row['s']:>12}  {row['c']}")
        cur.execute(
            """SELECT COUNT(*) AS c FROM file_metadata f
               JOIN albums a ON a.id = f.album_id
               JOIN users u ON u.id = a.user_id
               WHERE u.email = %s AND f.content_id LIKE %s
                 AND f.gps_source IS NULL AND f.exif_date_source IS NULL""",
            (args.email, MARKER + "%"),
        )
        print(f"{'un-finalized':>12}  {cur.fetchone()['c']}")


def summarise(totals):
    print(
        f"\nalbums touched {totals['albums']}, uploaded {totals['uploaded']}, "
        f"already there {totals['skipped']}, missing in v1 S3 {totals['missing']}"
    )


# --------------------------------------------------------------------------- main


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--email", required=True, help="account to migrate, on both sides")
    parser.add_argument(
        "--phase", choices=("upload", "finalize", "status"), default="upload"
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0, help="stop after N uploads")
    parser.add_argument("--include-empty-albums", action="store_true")
    parser.add_argument(
        "--publish",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="mark migrated albums published, as v1 albums were shareable (default: yes)",
    )
    parser.add_argument(
        "--force", action="store_true", help="finalize: proceed while rows are still processing"
    )
    args = parser.parse_args()

    v1 = connect("V1")
    v2 = connect("V2")
    try:
        if args.phase == "upload":
            phase_upload(args, v1, v2, s3_source(), s3_target())
        elif args.phase == "finalize":
            phase_finalize(args, v1, v2)
        else:
            phase_status(args, v1, v2)
    finally:
        v1.close()
        v2.close()


if __name__ == "__main__":
    main()
