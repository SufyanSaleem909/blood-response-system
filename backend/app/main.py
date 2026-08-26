from fastapi import FastAPI

app = FastAPI(title="Blood Response System API")

@app.get("/health")
def health_check():
    return {"status": "ok"}