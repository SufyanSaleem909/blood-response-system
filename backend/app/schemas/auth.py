from pydantic import BaseModel


class OtpRequest(BaseModel):
    phone_number: str


class OtpVerify(BaseModel):
    phone_number: str
    code: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str | None = None
    is_new_user: bool