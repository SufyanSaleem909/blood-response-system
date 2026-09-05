from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session
from geoalchemy2.functions import ST_MakePoint, ST_SetSRID

from app.api.deps import get_current_user
from app.core.security import create_access_token
from app.db.session import get_db
from app.models.user import User
from app.schemas.user import UserCreate, UserOut

router = APIRouter(prefix="/users", tags=["users"])


class AvailabilityUpdate(BaseModel):
    is_donor_available: bool


@router.post("/", response_model=UserOut, status_code=201)
def create_user(payload: UserCreate, db: Session = Depends(get_db)):
    existing = db.execute(
        select(User).where(User.phone_number == payload.phone_number)
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=400, detail="Phone number already registered")

    new_user = User(
        phone_number=payload.phone_number,
        full_name=payload.full_name,
        blood_type=payload.blood_type,
        last_donation_date=payload.last_donation_date,
        fcm_token=payload.fcm_token,
        location=ST_SetSRID(ST_MakePoint(payload.longitude, payload.latitude), 4326),
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    token = create_access_token(str(new_user.id), new_user.phone_number)

    result = UserOut.model_validate(new_user)
    result.access_token = token
    return result


@router.get("/me", response_model=UserOut)
def get_me(current_user: User = Depends(get_current_user)):
    return current_user


@router.patch("/me/availability", response_model=UserOut)
def update_availability(
    payload: AvailabilityUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    current_user.is_donor_available = payload.is_donor_available
    db.commit()
    db.refresh(current_user)
    return current_user


@router.get("/{user_id}", response_model=UserOut)
def get_user(user_id: str, db: Session = Depends(get_db)):
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.get("/", response_model=list[UserOut])
def list_users(phone_number: Optional[str] = None, db: Session = Depends(get_db)):
    query = select(User)
    if phone_number:
        query = query.where(User.phone_number == phone_number)
    users = db.execute(query.order_by(User.created_at.desc()).limit(50)).scalars().all()
    return users