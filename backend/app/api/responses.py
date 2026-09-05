from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.blood_request import BloodRequest
from app.models.response import Response
from app.models.user import User as UserModel
from app.schemas.response import ResponseCreate, ResponseOut
from app.services.notifications import send_response_notification

router = APIRouter(prefix="/blood-requests", tags=["responses"])


@router.post("/{request_id}/respond", response_model=ResponseOut, status_code=201)
def respond_to_request(
    request_id: str,
    payload: ResponseCreate,
    db: Session = Depends(get_db),
    current_user: UserModel = Depends(get_current_user),
):
    # 1. Security Check First: Ensure donor is responding for themselves
    if str(current_user.id) != str(payload.donor_id):
        raise HTTPException(
            status_code=403, 
            detail="Cannot respond on behalf of another user"
        )

    # 2. Status Validation
    if payload.status not in ("accepted", "declined"):
        raise HTTPException(
            status_code=400, 
            detail="status must be 'accepted' or 'declined'"
        )

    # 3. Request & Donor Validation
    req = db.get(BloodRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Blood request not found")

    donor = db.get(UserModel, payload.donor_id)
    if not donor:
        raise HTTPException(status_code=404, detail="Donor not found")

    # 4. Update existing response or create a new one
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
        result = existing
    else:
        new_response = Response(
            request_id=request_id,
            donor_id=payload.donor_id,
            status=payload.status,
        )
        db.add(new_response)
        db.commit()
        db.refresh(new_response)
        result = new_response

    # 5. Push Notification to Requester
    requester = db.get(UserModel, req.requester_id)
    if requester and requester.fcm_token:
        send_response_notification(
            fcm_token=requester.fcm_token,
            donor_name=donor.full_name,
            hospital_name=req.hospital_name,
            status=payload.status,
        )

    return result


@router.get("/{request_id}/responses", response_model=list[ResponseOut])
def list_responses(request_id: str, db: Session = Depends(get_db)):
    req = db.get(BloodRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Blood request not found")

    responses = (
        db.execute(select(Response).where(Response.request_id == request_id))
        .scalars()
        .all()
    )
    return responses