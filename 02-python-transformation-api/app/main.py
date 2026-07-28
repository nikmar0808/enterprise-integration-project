from fastapi import FastAPI
from app.api.transform import router as transform_router

app = FastAPI(
    title="Smart Meter Data Transformation API",
    description="High-speed ingestion and validation engine for grid smart-meter telemetry.",
    version="1.0.0"
)

# Base health-check endpoint
@app.get("/")
def read_root():
    return {"status": "operational", "engine": "FastAPI 0.115.6", "runtime": "Python 3.13"}

# Register the decoupled enterprise ingestion routers
app.include_router(transform_router)
