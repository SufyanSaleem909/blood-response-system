from datetime import date, timedelta
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session
from geoalchemy2.functions import ST_SetSRID, ST_MakePoint
from app.api.deps import get_current_user
from app.models.user import User as UserModel
from app.db.session import get_db
from app.models.user import User
from app.models.blood_request import BloodRequest
from app.schemas.blood_request import BloodRequestCreate, BloodRequestOut
from app.services.matching import COMPATIBLE_DONORS
from app.services.notifications import send_match_notification

router = APIRouter(prefix="/blood-requests", tags=["blood-requests"])


def is_eligible(last_donation_date: date | None) -> bool:
    """Check if donor completed the mandatory 90-day waiting period."""
    if last_donation_date is None:
        return True
    return date.today() >= last_donation_date + timedelta(days=90)


@router.post("/", response_model=BloodRequestOut, status_code=201)
def create_blood_request(
    payload: BloodRequestCreate,
    db: Session = Depends(get_db),
    current_user: UserModel = Depends(get_current_user),
):
    if str(current_user.id) != str(payload.requester_id):
        raise HTTPException(status_code=403, detail="Cannot create a request on behalf of another user")

    requester = db.get(User, payload.requester_id)
    if not requester:
        raise HTTPException(status_code=404, detail="Requester not found")
    ...  # rest of the function body stays exactly the same

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

    # Push notifications to compatible, eligible nearby donors (within 10km)
    compatible_types = COMPATIBLE_DONORS.get(payload.blood_type_needed, [])
    query = text("""
        SELECT fcm_token, last_donation_date,
               ST_Distance(location::geography, ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography) / 1000 AS distance_km
        FROM users
        WHERE id != :requester_id
          AND blood_type = ANY(:compatible_types)
          AND is_donor_available = TRUE
          AND ST_DWithin(location::geography, ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography, 10000)
    """)
    rows = db.execute(query, {
        "requester_id": payload.requester_id,
        "lng": payload.longitude,
        "lat": payload.latitude,
        "compatible_types": compatible_types,
    }).mappings().all()

    for row in rows:
        if is_eligible(row["last_donation_date"]):
            send_match_notification(
                fcm_token=row["fcm_token"],
                blood_type=payload.blood_type_needed,
                hospital_name=payload.hospital_name,
                distance_km=round(row["distance_km"], 2),
            )

    return new_request


@router.get("/{request_id}", response_model=BloodRequestOut)
def get_blood_request(request_id: str, db: Session = Depends(get_db)):
    req = db.get(BloodRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Blood request not found")
    return req


@router.get("/{request_id}/matches")
def get_matches(request_id: str, radius_km: int = 10, db: Session = Depends(get_db)):
    req = db.get(BloodRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Blood request not found")

    compatible_types = COMPATIBLE_DONORS.get(req.blood_type_needed, [])

    query = text("""
        SELECT id, full_name, phone_number, blood_type, last_donation_date,
               ST_Distance(location::geography, (SELECT location::geography FROM blood_requests WHERE id = :req_id)) / 1000 AS distance_km
        FROM users
        WHERE id != :requester_id
          AND blood_type = ANY(:compatible_types)
          AND is_donor_available = TRUE
          AND ST_DWithin(location::geography, (SELECT location::geography FROM blood_requests WHERE id = :req_id), :radius_m)
        ORDER BY distance_km ASC
        LIMIT 50
    """)
    rows = db.execute(query, {
        "req_id": request_id,
        "requester_id": req.requester_id,
        "compatible_types": compatible_types,
        "radius_m": radius_km * 1000,
    }).mappings().all()

    matches = [dict(r) for r in rows if is_eligible(r["last_donation_date"])]
    for m in matches:
        m["distance_km"] = round(m["distance_km"], 2)
        m["id"] = str(m["id"])
        m["last_donation_date"] = str(m["last_donation_date"]) if m["last_donation_date"] else None

    return {
        "request_id": request_id,
        "blood_type_needed": req.blood_type_needed,
        "matches": matches
    }