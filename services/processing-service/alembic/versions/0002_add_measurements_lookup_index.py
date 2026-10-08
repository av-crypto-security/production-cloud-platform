"""add measurements lookup index

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-07
"""

from alembic import op


revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


INDEX_NAME = "ix_measurements_bridge_id_timestamp"


def upgrade():
    with op.get_context().autocommit_block():
        op.create_index(
            INDEX_NAME,
            "measurements",
            ["bridge_id", "timestamp"],
            unique=False,
            postgresql_concurrently=True,
        )


def downgrade():
    with op.get_context().autocommit_block():
        op.drop_index(
            INDEX_NAME,
            table_name="measurements",
            postgresql_concurrently=True,
        )
