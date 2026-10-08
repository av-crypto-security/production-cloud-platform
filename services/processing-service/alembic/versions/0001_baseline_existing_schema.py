"""baseline existing schema

Revision ID: 0001
Revises:
Create Date: 2026-10-07
"""

from alembic import op
import sqlalchemy as sa


revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "measurements",
        sa.Column(
            "id",
            sa.Integer(),
            primary_key=True,
            autoincrement=True,
            nullable=False,
        ),
        sa.Column(
            "bridge_id",
            sa.String(length=32),
            nullable=True,
        ),
        sa.Column(
            "timestamp",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
        sa.Column(
            "temperature",
            sa.Float(),
            nullable=True,
        ),
        sa.Column(
            "humidity",
            sa.Float(),
            nullable=True,
        ),
        sa.Column(
            "vibration",
            sa.Float(),
            nullable=True,
        ),
        sa.Column(
            "tilt",
            sa.Float(),
            nullable=True,
        ),
        sa.Column(
            "processed",
            sa.Boolean(),
            nullable=True,
            server_default=sa.text("false"),
        ),
    )

    op.create_table(
        "alerts",
        sa.Column(
            "id",
            sa.Integer(),
            primary_key=True,
            autoincrement=True,
            nullable=False,
        ),
        sa.Column(
            "bridge_id",
            sa.String(length=32),
            nullable=True,
        ),
        sa.Column(
            "timestamp",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
        sa.Column(
            "alert_type",
            sa.String(length=64),
            nullable=True,
        ),
        sa.Column(
            "severity",
            sa.String(length=32),
            nullable=True,
        ),
        sa.Column(
            "message",
            sa.Text(),
            nullable=True,
        ),
    )


def downgrade():
    op.drop_table("alerts")
    op.drop_table("measurements")
