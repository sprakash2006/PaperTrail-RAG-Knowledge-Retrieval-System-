"""
Core RAG engine — format-aware ingestion, conflict detection, and email fetching.

These modules are storage-agnostic and shared by the FastAPI services/routers.
"""

from engine.rag_ingestor import FileIngestor
from engine.conflict_detector import ConflictDetector
from engine.email_fetcher import EmailFetcher

__all__ = ["FileIngestor", "ConflictDetector", "EmailFetcher"]
