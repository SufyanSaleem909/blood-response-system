import uuid
from datetime import datetime

from pydantic import BaseModel


class ResponseCreate(BaseModel):
    donor_id: uuid.UUID
    status: str  # "accepted" or "declined"


class ResponseOut(BaseModel):
    id: uuid.UUID
    request_id: uuid.UUID
    donor_id: uuid.UUID
    status: str
    responded_at: datetime

    class Config:
        from_attributes = True