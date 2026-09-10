import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


class ResponseCreate(BaseModel):
    donor_id: uuid.UUID
    status: str  # "accepted" or "declined"


class StatusMessageUpdate(BaseModel):
    status_message: str


class ResponseOut(BaseModel):
    id: uuid.UUID
    request_id: uuid.UUID
    donor_id: uuid.UUID
    status: str
    status_message: Optional[str] = None
    responded_at: datetime

    class Config:
        from_attributes = True