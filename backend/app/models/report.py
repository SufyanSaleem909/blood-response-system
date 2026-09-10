import uuid
from datetime import datetime

from sqlalchemy import Column, String, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID

from app.db.session import Base


class Report(Base):
    __tablename__ = "reports"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    reporter_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    reported_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    request_id = Column(UUID(as_uuid=True), ForeignKey("blood_requests.id"), nullable=True)
    reason = Column(String, nullable=False)
    status = Column(String, default="pending", nullable=False)  # pending / reviewed / actioned
    created_at = Column(DateTime(timezone=True), server_default=func.now())