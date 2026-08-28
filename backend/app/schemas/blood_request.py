import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class BloodRequestCreate(BaseModel):
    requester_id: uuid.UUID
    blood_type_needed: str = Field(..., examples=["O-"])
    units_needed: int = Field(..., gt=0)
    hospital_name: str
    latitude: float
    longitude: float
    urgency: str = "critical"


class BloodRequestOut(BaseModel):
    id: uuid.UUID
    requester_id: uuid.UUID
    blood_type_needed: str
    units_needed: int
    hospital_name: str
    urgency: str
    status: str
    created_at: datetime

    class Config:
        from_attributes = True