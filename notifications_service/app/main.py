 """
FastAPI entry point for the EcoTrace Notification Microservice.

This service provides:
- Firebase Cloud Messaging (FCM)
- Notification APIs
- Health checks
- Swagger documentation

Deployment:
- Render
- Uvicorn
"""

import logging
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.notifications.firebase import initialize_firebase
from app.notifications.routes import router

# ---------------------------------------------------------
# Logging Configuration
# ---------------------------------------------------------

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
)

logger = logging.getLogger("ecotrace")

# ---------------------------------------------------------
# Initialize Firebase
# ---------------------------------------------------------

initialize_firebase()

logger.info("Firebase initialized successfully.")

# ---------------------------------------------------------
# FastAPI Application
# ---------------------------------------------------------

app = FastAPI(
    title="EcoTrace Push Notification API",
    description="""
EcoTrace Push Notification Service.

Features:

- Firebase Cloud Messaging (FCM)
- Device Token Registration
- Push Notifications
- Announcements
- Admin Messages
- Security Alerts
- Notification History
""",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# ---------------------------------------------------------
# CORS Configuration
# ---------------------------------------------------------

origins = [
    origin.strip()
    for origin in os.getenv("API_ALLOWED_ORIGINS", "").split(",")
    if origin.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins or ["*"],
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=False if not origins else True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------
# Register Routes
# ---------------------------------------------------------

app.include_router(router)

# ---------------------------------------------------------
# Root Endpoint
# ---------------------------------------------------------

@app.get("/", tags=["System"])
async def root():
    """
    Root endpoint.
    """
    return {
        "success": True,
        "message": "Welcome to EcoTrace Push Notification API",
        "service": "EcoTrace Notification Service",
        "version": "1.0.0",
        "status": "running",
        "documentation": "/docs",
        "redoc": "/redoc",
        "health": "/health",
    }

# ---------------------------------------------------------
# Health Check
# ---------------------------------------------------------

@app.get("/health", tags=["System"])
async def health():
    """
    Health endpoint used by Render.
    """
    return {
        "success": True,
        "status": "healthy",
        "service": "ecotrace-notifications",
        "version": "1.0.0",
    }

# ---------------------------------------------------------
# Startup Event
# ---------------------------------------------------------

@app.on_event("startup")
async def startup_event():
    logger.info("===========================================")
    logger.info(" EcoTrace Notification Service Started")
    logger.info(" Version : 1.0.0")
    logger.info("===========================================")

# ---------------------------------------------------------
# Shutdown Event
# ---------------------------------------------------------

@app.on_event("shutdown")
async def shutdown_event():
    logger.info("EcoTrace Notification Service Stopped.")