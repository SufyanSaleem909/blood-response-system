from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from geoalchemy2.functions import ST_SetSRID, ST_MakePoint

from app.db.session import get_db
from app.models.user import User
from app.models.blood_request import BloodRequest
from app.schemas.blood_request import BloodRequestCreate, BloodRequestOut

router = APIRouter(prefix="/blood-requests", tags=["blood-requests"])


@router.post("/", response_model=BloodRequestOut, status_code=201)
def create_blood_request(payload: BloodRequestCreate, db: Session = Depends(get_db)):
    requester = db.get(User, payload.requester_id)
    if not requester:
        raise HTTPException(status_code=404, detail="Requester not found")

    new_request = BloodRequest(
        requester_id=payload.requester_id,
        blood_type_needed=payload.blood_type_needed,
        units_needed=payload.units_needed,
        hospital_name=payload.hospital_name,
        urgency=payload.urgency,
        location=ST_SetSRID(ST_MakePoint(payload.longitude, payload.latitude), 4326),
    )
    db.add(new_request)
    db.commit()
    db.refresh(new_request)
    return new_request


@router.get("/{request_id}", response_model=BloodRequestOut)
def get_blood_request(request_id: str, db: Session = Depends(get_db)):
    req = db.get(BloodRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Blood request not found")
    return req