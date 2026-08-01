"""FastAPI entry point for the EcoTrace notification microservice."""

import logging
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.notifications.firebase import initialize_firebase
from app.notifications.routes import router

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

initialize_firebase()

app = FastAPI(
    title="EcoTrace Push Notification API",
    version="1.0.0",
    description="Authenticated Firebase Cloud Messaging service for EcoTrace.",
)

origins = [value.strip() for value in os.getenv("API_ALLOWED_ORIGINS", "").split(",") if value.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins or ["*"],
    allow_credentials=bool(origins),
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-EcoTrace-Event-Key"],
)

app.include_router(router)


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    """Return service health for Render."""
    return {"status": "ok", "service": "ecotrace-notifications", "version": "1.0.0"}
