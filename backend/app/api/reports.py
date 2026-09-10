from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import select
from pydantic import BaseModel

from app.db.session import get_db
from app.models.user import User
from app.models.report import Report
from app.schemas.report import ReportCreate, ReportOut
from app.api.deps import get_current_user, require_admin

router = APIRouter(prefix="/reports", tags=["reports"])


class BanRequest(BaseModel):
    banned: bool


@router.post("/", response_model=ReportOut, status_code=201)
def create_report(
    payload: ReportCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if str(payload.reported_user_id) == str(current_user.id):
        raise HTTPException(status_code=400, detail="Cannot report yourself")

    reported = db.get(User, payload.reported_user_id)
    if not reported:
        raise HTTPException(status_code=404, detail="Reported user not found")

    report = Report(
        reporter_id=current_user.id,
        reported_user_id=payload.reported_user_id,
        request_id=payload.request_id,
        reason=payload.reason,
    )
    db.add(report)
    db.commit()
    db.refresh(report)
    return report


@router.get("/", response_model=list[ReportOut])
def list_reports(
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    reports = db.execute(
        select(Report).order_by(Report.created_at.desc())
    ).scalars().all()
    return reports


@router.patch("/users/{user_id}/ban")
def set_user_banned(
    user_id: str,
    payload: BanRequest,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.is_banned = payload.banned
    db.commit()
    return {"user_id": user_id, "is_banned": user.is_banned}