from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    secret_key: str
    environment: str = "development"
    admin_phone_number: str = "+923102691636"

    class Config:
        env_file = ".env"

settings = Settings()