from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from geoalchemy2.functions import ST_SetSRID, ST_MakePoint

from app.db.session import get_db
from app.models.user import User
from app.models.blood_request import BloodRequest
from app.schemas.blood_request import BloodRequestCreate, BloodRequestOut
from datetime import date, timedelta
from sqlalchemy import text
from app.services.matching import COMPATIBLE_DONORS

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

from datetime import date, timedelta
from sqlalchemy import text
from app.services.matching import COMPATIBLE_DONORS


def is_eligible(last_donation_date):
    if last_donation_date is None:
        return True
    return date.today() >= last_donation_date + timedelta(days=90)


@router.get("/{request_id}/matches")
def get_matches(request_id: str, radius_km: int = 10, db: Session = Depends(get_db)):
    req = db.get(BloodRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Blood request not found")

    compatible_types = COMPATIBLE_DONORS[req.blood_type_needed]

    query = text("""
        SELECT id, full_name, phone_number, blood_type, last_donation_date,
               ST_Distance(location, (SELECT location FROM blood_requests WHERE id = :req_id)) / 1000 AS distance_km
        FROM users
        WHERE blood_type = ANY(:compatible_types)
          AND is_donor_available = TRUE
          AND ST_DWithin(location, (SELECT location FROM blood_requests WHERE id = :req_id), :radius_m)
        ORDER BY distance_km ASC
        LIMIT 50
    """)
    rows = db.execute(query, {
        "req_id": request_id,
        "compatible_types": compatible_types,
        "radius_m": radius_km * 1000,
    }).mappings().all()

    matches = [dict(r) for r in rows if is_eligible(r["last_donation_date"])]
    for m in matches:
        m["distance_km"] = round(m["distance_km"], 2)
        m["id"] = str(m["id"])
        m["last_donation_date"] = str(m["last_donation_date"]) if m["last_donation_date"] else None

    return {"request_id": request_id, "blood_type_needed": req.blood_type_needed, "matches": matches}