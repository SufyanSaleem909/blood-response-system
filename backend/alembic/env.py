import os
import sys

sys.path.append(os.getcwd())

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from app.core.config import settings
from app.db.session import Base
from app.models import BloodRequest, Response, User  # noqa: F401

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Interpret the config file for Python logging.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata

# Tables owned by PostGIS / Tiger Geocoder extensions that Alembic must ignore

def include_object(object, name, type_, reflected, compare_to):
    # Only compare/manage tables that are defined in our own SQLAlchemy
    # models (target_metadata). Everything else in the database (PostGIS
    # extension tables like tiger_geocoder's edges/faces/tabblock/etc.,
    # topology tables, spatial_ref_sys) is left alone entirely.
    if type_ == "table":
        return name in target_metadata.tables
    return True


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        include_object=include_object,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode."""
    connectable = engine_from_config(
        {"sqlalchemy.url": settings.database_url},
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            include_object=include_object,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()