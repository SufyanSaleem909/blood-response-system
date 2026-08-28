import uuid

from sqlalchemy import Column, String, Integer, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from geoalchemy2 import Geography

from app.db.session import Base


class BloodRequest(Base):
    __tablename__ = "blood_requests"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    requester_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    blood_type_needed = Column(String(3), nullable=False)
    units_needed = Column(Integer, nullable=False)
    hospital_name = Column(String(200), nullable=False)
    location = Column(Geography(geometry_type="POINT", srid=4326), nullable=False)
    urgency = Column(String(20), default="critical", nullable=False)
    status = Column(String(20), default="open", nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=True)