from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field

class MeterReading(BaseModel):
    """
    Validates individual smart-meter telemetry metrics intervals.
    """
    timestamp: datetime = Field(description="ISO 8601 formatted event date-time.")
    kwh_value: float = Field(gt=0.0, description="Active energy consumption reading. Must be positive.")
    voltage: Optional[float] = Field(default=None, ge=100.0, le=300.0, description="Grid voltage drop check.")


class SmartMeterPayload(BaseModel):
    """
    Defines the structural boundary contract for raw bulk grid transmissions.
    """
    meter_id: str = Field(min_length=5, max_length=20, description="Unique utility asset identifier code.")
    grid_zone: str = Field(description="Regional grid operational sector zone code.")
    readings: List[MeterReading] = Field(description="Array collections of timestamped interval metrics.")
