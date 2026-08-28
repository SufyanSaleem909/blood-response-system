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