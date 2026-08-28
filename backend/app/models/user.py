import uuid
from datetime import date, datetime

from sqlalchemy import Column, String, Boolean, Date, DateTime, func
from sqlalchemy.dialects.postgresql import UUID
from geoalchemy2 import Geography

from app.db.session import Base


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    phone_number = Column(String(20), unique=True, nullable=False, index=True)
    full_name = Column(String(100), nullable=False)
    blood_type = Column(String(3), nullable=False)  # e.g. "O+", "O-", "AB+"
    is_donor_available = Column(Boolean, default=True, nullable=False)
    last_donation_date = Column(Date, nullable=True)
    location = Column(Geography(geometry_type="POINT", srid=4326), nullable=True)
    fcm_token = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())