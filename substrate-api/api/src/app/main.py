"""
Clearinghouse API - IP Licensing Infrastructure for the AI Era

FastAPI application for managing intellectual property rights,
licensing, and governance.
"""
import os
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.deps import get_db, close_db
from middleware.auth import AuthMiddleware

# Routes
from app.routes import health, workspaces, catalogs, rights_entities, proposals, licenses, timeline, assets, jobs

log = logging.getLogger("uvicorn.error")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler for startup/shutdown."""
    log.info("Starting Clearinghouse API...")
    # Initialize database connection pool
    await get_db()
    log.info("Database connection established")
    yield
    # Cleanup
    log.info("Shutting down Clearinghouse API...")
    await close_db()
    log.info("Database connection closed")


app = FastAPI(
    title="Clearinghouse API",
    description="IP Licensing Infrastructure for the AI Era",
    version="0.1.0",
    lifespan=lifespan,
)

# CORS configuration
cors_origins = os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Auth middleware with exemptions
app.add_middleware(
    AuthMiddleware,
    exempt_paths={"/", "/health", "/docs", "/openapi.json", "/redoc"},
    exempt_prefixes={"/health/"},
)

# Include routers
app.include_router(health.router, tags=["Health"])
app.include_router(workspaces.router, prefix="/api/v1", tags=["Workspaces"])
app.include_router(catalogs.router, prefix="/api/v1", tags=["Catalogs"])
app.include_router(rights_entities.router, prefix="/api/v1", tags=["Rights Entities"])
app.include_router(proposals.router, prefix="/api/v1", tags=["Governance"])
app.include_router(licenses.router, prefix="/api/v1", tags=["Licensing"])
app.include_router(timeline.router, prefix="/api/v1", tags=["Timeline"])
app.include_router(assets.router, prefix="/api/v1", tags=["Assets"])
app.include_router(jobs.router, prefix="/api/v1", tags=["Processing Jobs"])


@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "name": "Clearinghouse API",
        "version": "0.1.0",
        "description": "IP Licensing Infrastructure for the AI Era",
    }
