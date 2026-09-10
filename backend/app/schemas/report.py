import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class ReportCreate(BaseModel):
    reported_user_id: uuid.UUID
    request_id: Optional[uuid.UUID] = None
    reason: str


class ReportOut(BaseModel):
    id: uuid.UUID
    reporter_id: uuid.UUID
    reported_user_id: uuid.UUID
    request_id: Optional[uuid.UUID] = None
    reason: str
    status: str
    created_at: datetime

    class Config:
        from_attributes = True