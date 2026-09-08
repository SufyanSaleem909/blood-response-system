from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security import (
    OTP_EXPIRE_MINUTES,
    OTP_MAX_ATTEMPTS,
    OTP_RESEND_COOLDOWN_SECONDS,
    create_access_token,
    generate_otp,
    hash_otp,
    verify_otp_hash,
)
from app.db.session import get_db
from app.models.otp_code import OtpCode
from app.models.user import User
from app.schemas.auth import OtpRequest, OtpVerify, TokenOut

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/request-otp")
def request_otp(payload: OtpRequest, db: Session = Depends(get_db)):
    # Cooldown: block resending too soon after the last request for this number
    last_otp = db.execute(
        select(OtpCode)
        .where(OtpCode.phone_number == payload.phone_number)
        .order_by(OtpCode.created_at.desc())
    ).scalars().first()

    if last_otp:
        elapsed = datetime.now(timezone.utc) - last_otp.created_at.replace(tzinfo=timezone.utc)
        if elapsed < timedelta(seconds=OTP_RESEND_COOLDOWN_SECONDS):
            wait_seconds = int(OTP_RESEND_COOLDOWN_SECONDS - elapsed.total_seconds())
            raise HTTPException(
                status_code=429,
                detail=f"Please wait {wait_seconds}s before requesting another code",
            )

    # Invalidate any previous unused OTPs for this number so only the newest code is ever valid at once
    db.execute(
        OtpCode.__table__.delete().where(OtpCode.phone_number == payload.phone_number)
    )

    code = generate_otp()
    otp = OtpCode(
        phone_number=payload.phone_number,
        code_hash=hash_otp(code),
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=OTP_EXPIRE_MINUTES),
    )
    db.add(otp)
    db.commit()

    print(f"\n[DEV OTP] Code for {payload.phone_number}: {code}\n")

    return {"message": "OTP sent (check backend console in dev mode)"}


@router.post("/verify-otp", response_model=TokenOut)
def verify_otp(payload: OtpVerify, db: Session = Depends(get_db)):
    otp = db.execute(
        select(OtpCode)
        .where(OtpCode.phone_number == payload.phone_number)
        .order_by(OtpCode.created_at.desc())
    ).scalars().first()

    if not otp:
        raise HTTPException(status_code=400, detail="No OTP requested for this number")

    if datetime.now(timezone.utc) > otp.expires_at.replace(tzinfo=timezone.utc):
        db.delete(otp)
        db.commit()
        raise HTTPException(status_code=400, detail="OTP expired, request a new one")

    if otp.attempts >= OTP_MAX_ATTEMPTS:
        db.delete(otp)
        db.commit()
        raise HTTPException(status_code=429, detail="Too many incorrect attempts, request a new code")

    if not verify_otp_hash(payload.code, otp.code_hash):
        otp.attempts += 1
        db.commit()
        remaining = OTP_MAX_ATTEMPTS - otp.attempts
        raise HTTPException(
            status_code=400,
            detail=f"Invalid OTP code ({remaining} attempts remaining)",
        )

    user = db.execute(
        select(User).where(User.phone_number == payload.phone_number)
    ).scalar_one_or_none()

    db.delete(otp)
    db.commit()

    if user:
        token = create_access_token(str(user.id), user.phone_number)
        return TokenOut(access_token=token, user_id=str(user.id), is_new_user=False)

    token = create_access_token("pending", payload.phone_number)
    return TokenOut(access_token=token, user_id=None, is_new_user=True)