from fastapi import APIRouter, HTTPException, status
from app.schemas.meter import SmartMeterPayload

# APIRouter acts like a mini-ESB router that attaches to the main engine later
router = APIRouter(prefix="/api/v1", tags=["Ingestion & Transformation"])

@router.post("/transform", status_code=status.HTTP_200_OK)
async def validate_and_transform_payload(payload: SmartMeterPayload):
    """
    Ingests raw smart-meter streams, enforces validation schemas, and processes data frames.
    """
    try:
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
