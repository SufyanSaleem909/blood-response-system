from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import select
from geoalchemy2.functions import ST_SetSRID, ST_MakePoint
from typing import Optional
from app.db.session import get_db
from app.models.user import User
from app.schemas.user import UserCreate, UserOut

router = APIRouter(prefix="/users", tags=["users"])


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
        location=ST_SetSRID(ST_MakePoint(payload.longitude, payload.latitude), 4326),
        fcm_token=payload.fcm_token,
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return new_user


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