from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import select
from geoalchemy2.functions import ST_SetSRID, ST_MakePoint

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