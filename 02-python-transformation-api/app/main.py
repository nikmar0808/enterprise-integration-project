import logging
from fastapi import FastAPI
from app.api.transform import router as transform_router
from app.config import settings

# Configure unified structured logging for the application lifecycle
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - [%(name)s] - %(message)s"
)
logger = logging.getLogger(__name__)

# Initialize the core FastAPI Application Engine using centralized configuration settings
app = FastAPI(
    title=settings.APP_TITLE,
    description="High-speed ingestion and validation engine for grid smart-meter telemetry.",
    version=settings.APP_VERSION
)

@app.on_event("startup")
def startup_event():
    """
    Triggers an audit log entry on system initialization to verify configuration states.
    """
    logger.info("Initializing Enterprise Transformation Service Core...")
    logger.info(f"Target Configuration Locked -> Title: {settings.APP_TITLE} | Version: {settings.APP_VERSION}")

# Base health-check endpoint
@app.get("/")
def read_root():
    return {
        "status": "operational", 
        "engine": "FastAPI", 
        "version": settings.APP_VERSION
    }

# Register the decoupled enterprise ingestion routers
app.include_router(transform_router)
