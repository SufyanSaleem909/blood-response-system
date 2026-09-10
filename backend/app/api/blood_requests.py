from datetime import date, datetime, timedelta, timezone
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select, text
from sqlalchemy.orm import Session
from geoalchemy2.functions import ST_MakePoint, ST_SetSRID

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.blood_request import BloodRequest
from app.models.response import Response
from app.models.user import User
from app.schemas.blood_request import BloodRequestCreate, BloodRequestOut
from app.schemas.response import ResponseOut
from app.services.matching import COMPATIBLE_DONORS
from app.services.notifications import send_match_notification

router = APIRouter(prefix="/blood-requests", tags=["blood-requests"])

URGENCY_EXPIRY_HOURS = {
    "critical": 6,
    "urgent": 24,
    "planned": 72,
}


class StatusUpdate(BaseModel):
    status: str  # "fulfilled" or "cancelled"


def is_eligible(last_donation_date: date | None) -> bool:
    """Check if donor completed the mandatory 90-day waiting period."""
    if last_donation_date is None:
        return True
    return date.today() >= last_donation_date + timedelta(days=90)


def _apply_lazy_expiry(req: BloodRequest, db: Session) -> BloodRequest:
    """If a request's expiry has passed but it's still marked open, flip it
    to expired now. Avoids needing a background scheduler for this MVP."""
    if (
        req.status == "open"
        and req.expires_at
        and datetime.now(timezone.utc) > req.expires_at.replace(tzinfo=timezone.utc)
    ):
        req.status = "expired"
        db.commit()
        db.refresh(req)
    return req


@router.post("/", response_model=BloodRequestOut, status_code=201)
def create_blood_request(
    payload: BloodRequestCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if str(current_user.id) != str(payload.requester_id):
        raise HTTPException(
            status_code=403, detail="Cannot create a request on behalf of another user"
        )

    requester = db.get(User, payload.requester_id)
    if not requester:
        raise HTTPException(status_code=404, detail="Requester not found")

    expiry_hours = URGENCY_EXPIRY_HOURS.get(payload.urgency, 24)

    new_request = BloodRequest(
        requester_id=payload.requester_id,
        blood_type_needed=payload.blood_type_needed,
        units_needed=payload.units_needed,
        hospital_name=payload.hospital_name,
        urgency=payload.urgency,
        expires_at=datetime.now(timezone.utc) + timedelta(hours=expiry_hours),
        location=ST_SetSRID(ST_MakePoint(payload.longitude, payload.latitude), 4326),
    )
    db.add(new_request)
    db.commit()
    db.refresh(new_request)

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
    rows = db.execute(
        query,
        {
            "requester_id": payload.requester_id,
            "lng": payload.longitude,
            "lat": payload.latitude,
            "compatible_types": compatible_types,
        },
    ).mappings().all()

    seen_tokens = set()
    for row in rows:
        token = row["fcm_token"]
        if not token or token in seen_tokens:
            continue

        seen_tokens.add(token)

        if is_eligible(row["last_donation_date"]):
            send_match_notification(
                fcm_token=token,
                blood_type=payload.blood_type_needed,
                hospital_name=payload.hospital_name,
                distance_km=round(row["distance_km"], 2),
            )

    return new_request


@router.get("/", response_model=list[BloodRequestOut])
def list_blood_requests(status: Optional[str] = None, db: Session = Depends(get_db)):
    query = select(BloodRequest)
    if status:
        query = query.where(BloodRequest.status == status)
    requests = db.execute(
        query.order_by(BloodRequest.created_at.desc()).limit(50)
    ).scalars().all()
    return [_apply_lazy_expiry(r, db) for r in requests]


@router.get("/mine/requests", response_model=list[BloodRequestOut])
def my_requests(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    requests = db.execute(
        select(BloodRequest)
        .where(BloodRequest.requester_id == current_user.id)
        .order_by(BloodRequest.created_at.desc())
    ).scalars().all()
    return [_apply_lazy_expiry(r, db) for r in requests]


@router.get("/mine/responses", response_model=list[ResponseOut])
def my_responses(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    responses = db.execute(
        select(Response)
        .where(Response.donor_id == current_user.id)
        .order_by(Response.responded_at.desc())
    ).scalars().all()
    return responses


@router.get("/nearby/for-donor")
def nearby_requests_for_donor(
    radius_km: int = 10,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    compatible_needed_types = [
        needed for needed, donor_types in COMPATIBLE_DONORS.items()
        if current_user.blood_type in donor_types
    ]

    coords = db.execute(
        text("SELECT ST_X(location::geometry) AS lng, ST_Y(location::geometry) AS lat FROM users WHERE id = :donor_id"),
        {"donor_id": current_user.id}
    ).mappings().first()

    if not coords or coords["lng"] is None or coords["lat"] is None:
        return {"requests": []}

    query = text("""
        SELECT br.id, br.blood_type_needed, br.units_needed, br.hospital_name,
               br.urgency, br.status, br.created_at, br.expires_at,
               ST_Distance(br.location::geography, ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography) / 1000 AS distance_km,
               EXISTS (
                   SELECT 1 FROM responses r
                   WHERE r.request_id = br.id AND r.donor_id = :donor_id
               ) AS already_responded
        FROM blood_requests br
        WHERE br.status = 'open'
          AND (br.expires_at IS NULL OR br.expires_at > NOW())
          AND br.requester_id != :donor_id
          AND requester.is_banned = FALSE
          AND br.blood_type_needed = ANY(:compatible_needed_types)
          AND ST_DWithin(br.location::geography, ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography, :radius_m)
        ORDER BY distance_km ASC
        LIMIT 50
    """)

    rows = db.execute(query, {
        "donor_id": current_user.id,
        "lng": coords["lng"],
        "lat": coords["lat"],
        "compatible_needed_types": compatible_needed_types,
        "radius_m": radius_km * 1000,
    }).mappings().all()

    results = []
    for r in rows:
        d = dict(r)
        d["id"] = str(d["id"])
        d["distance_km"] = round(d["distance_km"], 2)
        d["created_at"] = str(d["created_at"])
        d["expires_at"] = str(d["expires_at"]) if d["expires_at"] else None
        results.append(d)

    return {"requests": results}


@router.get("/{request_id}", response_model=BloodRequestOut)
def get_blood_request(request_id: str, db: Session = Depends(get_db)):
    req = db.get(BloodRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Blood request not found")
    return _apply_lazy_expiry(req, db)


@router.get("/{request_id}/matches")
def get_matches(request_id: str, radius_km: int = 10, db: Session = Depends(get_db)):
    req = db.get(BloodRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Blood request not found")

    req = _apply_lazy_expiry(req, db)
    if req.status != "open":
        return {
            "request_id": request_id,
            "blood_type_needed": req.blood_type_needed,
            "matches": [],
            "status": req.status,
        }

    compatible_types = COMPATIBLE_DONORS.get(req.blood_type_needed, [])

    query = text("""
        SELECT id, full_name, phone_number, blood_type, last_donation_date,
               ST_Y(location::geometry) AS latitude,
               ST_X(location::geometry) AS longitude,
               ST_Distance(location::geography, (SELECT location::geography FROM blood_requests WHERE id = :req_id)) / 1000 AS distance_km
        FROM users
        WHERE id != :requester_id
          AND blood_type = ANY(:compatible_types)
          AND is_donor_available = TRUE
          AND is_banned = FALSE
          AND ST_DWithin(location::geography, (SELECT location::geography FROM blood_requests WHERE id = :req_id), :radius_m)
        ORDER BY distance_km ASC
        LIMIT 50
    """)
    rows = db.execute(
        query,
        {
            "req_id": request_id,
            "requester_id": req.requester_id,
            "compatible_types": compatible_types,
            "radius_m": radius_km * 1000,
        },
    ).mappings().all()

    matches = [dict(r) for r in rows if is_eligible(r["last_donation_date"])]
    for m in matches:
        m["distance_km"] = round(m["distance_km"], 2)
        m["id"] = str(m["id"])
        m["last_donation_date"] = (
            str(m["last_donation_date"]) if m["last_donation_date"] else None
        )

    hospital_coords = db.execute(
        text("SELECT ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng FROM blood_requests WHERE id = :req_id"),
        {"req_id": request_id}
    ).mappings().first()

    return {
        "request_id": request_id,
        "blood_type_needed": req.blood_type_needed,
        "hospital_name": req.hospital_name,
        "hospital_location": {
            "latitude": hospital_coords["lat"] if hospital_coords else None,
            "longitude": hospital_coords["lng"] if hospital_coords else None,
        },
        "matches": matches,
    }


@router.patch("/{request_id}/status", response_model=BloodRequestOut)
def update_request_status(
    request_id: str,
    payload: StatusUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if payload.status not in ("fulfilled", "cancelled"):
        raise HTTPException(status_code=400, detail="status must be 'fulfilled' or 'cancelled'")

    req = db.get(BloodRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Blood request not found")

    if str(req.requester_id) != str(current_user.id):
        raise HTTPException(status_code=403, detail="Only the requester can update this request's status")

    req.status = payload.status
    db.commit()
    db.refresh(req)
    return req