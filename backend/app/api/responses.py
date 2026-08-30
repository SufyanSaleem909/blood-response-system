from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import select

from app.db.session import get_db
from app.models.user import User
from app.models.blood_request import BloodRequest
from app.models.response import Response
from app.schemas.response import ResponseCreate, ResponseOut

router = APIRouter(prefix="/blood-requests", tags=["responses"])


@router.post("/{request_id}/respond", response_model=ResponseOut, status_code=201)
def respond_to_request(request_id: str, payload: ResponseCreate, db: Session = Depends(get_db)):
    if payload.status not in ("accepted", "declined"):
        raise HTTPException(status_code=400, detail="status must be 'accepted' or 'declined'")

    req = db.get(BloodRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Blood request not found")

    donor = db.get(User, payload.donor_id)
    if not donor:
        raise HTTPException(status_code=404, detail="Donor not found")

    # If this donor already responded to this request, update it instead of duplicating
    existing = db.execute(
        select(Response).where(
            Response.request_id == request_id,
            Response.donor_id == payload.donor_id,
        )
    ).scalar_one_or_none()

    if existing:
        existing.status = payload.status
        db.commit()
        db.refresh(existing)
        return existing

    new_response = Response(
        request_id=request_id,
        donor_id=payload.donor_id,
        status=payload.status,
    )
    db.add(new_response)
    db.commit()
    db.refresh(new_response)
    return new_response


@router.get("/{request_id}/responses", response_model=list[ResponseOut])
def list_responses(request_id: str, db: Session = Depends(get_db)):
    req = db.get(BloodRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Blood request not found")

    responses = db.execute(
        select(Response).where(Response.request_id == request_id)
    ).scalars().all()
    return responses