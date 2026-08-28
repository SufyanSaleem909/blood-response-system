import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, Field


class UserCreate(BaseModel):
    phone_number: str = Field(..., examples=["+923001234567"])
    full_name: str
    blood_type: str = Field(..., examples=["O-"])
    latitude: float
    longitude: float
    last_donation_date: Optional[date] = None


class UserOut(BaseModel):
    id: uuid.UUID
    phone_number: str
    full_name: str
    blood_type: str
    is_donor_available: bool
    last_donation_date: Optional[date] = None
    created_at: datetime

    class Config:
        from_attributes = True