# Step 1: Use a lightweight official Python 3.13 base runtime image
FROM python:3.13-slim

# Step 2: Establish system operational paths inside the container
WORKDIR /app

# Step 3: Inject system optimization flags to bypass overhead and freezing
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Step 4: Isolate dependency layer installation for fast rebuild caching
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Step 5: Transfer the functional enterprise application logic into the box
COPY . .

# Step 6: Expose the operational engine network gateway port
EXPOSE 8000

# Step 7: Launch the concurrent asynchronous Uvicorn execution loop
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
