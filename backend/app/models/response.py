import uuid

from sqlalchemy import Column, String, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID

from app.db.session import Base


class Response(Base):
    __tablename__ = "responses"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    request_id = Column(UUID(as_uuid=True), ForeignKey("blood_requests.id"), nullable=False)
    donor_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    status = Column(String(20), default="pending", nullable=False)  # pending/accepted/declined/arrived
    responded_at = Column(DateTime(timezone=True), server_default=func.now())