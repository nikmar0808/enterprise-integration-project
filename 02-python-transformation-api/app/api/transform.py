from fastapi import APIRouter, HTTPException, status
from app.schemas.meter import SmartMeterPayload

# FastAPI is built natively on top of the OpenAPI Specification (formerly known as Swagger). 
# Because we explicitly declared our data contracts using Pydantic and type hints, 
# the FastAPI engine dynamically analyzes your code structure at startup. 
# It maps out your routers, types, and constraints, compiles them into a standardized JSON configuration file behind the scenes, and 
# hosts an embedded web page to read that file.

# APIRouter acts like a mini-ESB router that attaches to the main engine later
# Instead of cluttering your main application file, an APIRouter lets you build isolated groups of endpoints. 
# The prefix="/api/v1" means every endpoint inside this file will automatically start with /api/v1 (e.g., /api/v1/transform). 
# This is how professional developers version their APIs so they don't break older client integrations when upgrading software.
router = APIRouter(prefix="/api/v1", tags=["Ingestion & Transformation"])

#The @ symbol is called a Decorator. Think of it as wrapping a specific function with extra powers. 
# Here, it tells FastAPI: "Listen for incoming HTTP POST requests hitting the /transform path, and 
# route that network traffic directly into the function below."
@router.post("/transform", status_code=status.HTTP_200_OK)

# This is the critical link. By typing the incoming payload variable as your Pydantic SmartMeterPayload class, 
# FastAPI automatically performs three background steps the moment a request hits the server:
# 1. It captures the raw incoming JSON text stream over the network.
# 2. It parses that text and validates it against every single rule we set up in meter.py 
#    (like checking if types match and numbers are positive).
# 3. If valid, it hands your function a clean, fully populated Python object ready for use. 
#    If invalid, it completely drops the connection and generates that detailed error report you saw in Swagger.
async def validate_and_transform_payload(payload: SmartMeterPayload):
    """
    Ingests raw smart-meter streams, enforces validation schemas, and processes data frames.
    """
    try:
        # Calculate some simple analytics on the validated payload
        # This is a highly optimized Python concept called a List Comprehension wrapped inside a sum() function. 
        # It loops through the array of meter readings, extracts just the numerical kwh_value from each record, and 
        # aggregates them into a single total.
        total_consumption = sum(reading.kwh_value for reading in payload.readings)
        total_records = len(payload.readings)
        
        return {
            "message": "Payload schema validated successfully",
            "metadata": {
                "processed_asset": payload.meter_id,
                "regional_zone": payload.grid_zone,
                "intervals_parsed": total_records
            },
            "analytics_summary": {
                "cumulative_kwh": round(total_consumption, 4),
                "average_load_per_interval": round(total_consumption / total_records, 4) if total_records > 0 else 0
            }
        }
    except Exception as err:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Enterprise data mapping breakdown error: {str(err)}"
        )
