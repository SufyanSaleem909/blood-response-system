## Alembic autogenerate + GeoAlchemy2 issues

1. Autogenerate does not add `import geoalchemy2` to the generated
   migration file even though it references `geoalchemy2.types.Geography`.
   Add the import manually.

2. GeoAlchemy2 automatically creates a GIST index on any Geography/Geometry
   column when its table is created (via a SQLAlchemy DDL event). Alembic's
   autogenerate does not know this and adds its own explicit
   `op.create_index(...)` for the same index, causing a
   `DuplicateTable` error on upgrade. Remove the redundant
   `op.create_index(...)` / `op.drop_index(...)` calls for geography
   columns from generated migrations — GeoAlchemy2 handles them.

   
## Alembic autogenerate picks up PostGIS's own tables

The postgis/postgis image (with tiger_geocoder + topology extensions)
creates many of its own tables (edges, faces, tabblock, zcta5,
countysub_lookup, spatial_ref_sys, etc.). Alembic's autogenerate compares
the whole database schema against our models and would try to drop these,
which fails since they're owned by extensions.

Fix: alembic/env.py's `include_object` filter restricts autogenerate to
only tables present in our own SQLAlchemy metadata (`target_metadata.tables`),
ignoring everything else in the database regardless of name. This is more
robust than maintaining an exclude-list, since PostGIS's exact table set
varies by version/extension.

## FlutterFire + Gradle version conflicts

Running `flutterfire configure` on an Android folder that was scaffolded
by an older Flutter version (or had manual Gradle edits) can produce
version conflicts, duplicate plugins blocks, or plugin resolution
failures that are hard to fix incrementally. The reliable fix: delete
`android/`, run `flutter create --platforms=android .` to regenerate it
matching the current Flutter SDK, reapply any manual manifest changes
(permissions etc.), then re-run `flutterfire configure` on the clean folder.

## Cannot pass a PostGIS geography value as a bound SQL parameter

Passing a `geography`/`geometry` result (fetched via `db.execute(...).scalar()`)
directly as a bound parameter in a later raw SQL query causes a syntax error —
psycopg2/SQLAlchemy can't serialize that Python object back into SQL. Instead,
fetch/pass plain `latitude`/`longitude` floats and reconstruct the point inside
the query with `ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography`, matching
the pattern used elsewhere (create_blood_request, get_matches).

## Adding a NOT NULL column to a table with existing rows

Alembic's autogenerate will happily generate `ALTER TABLE ... ADD COLUMN
... NOT NULL` for a new required field, but this fails if the table
already has rows, since Postgres can't backfill them with NULL. Fix:
add `server_default=sa.false()` (or the appropriate default) to the
`op.add_column(...)` call so existing rows get a real default value
instead of NULL.