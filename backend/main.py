
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from config import settings
from routers import auth, documents, chat, emails, tickets

app = FastAPI(
    title="Ignisia26 API",
    description="Enterprise RAG Pipeline with RBAC & Conflict Detection",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api")
app.include_router(documents.router, prefix="/api")
app.include_router(chat.router, prefix="/api")
app.include_router(emails.router, prefix="/api")
app.include_router(tickets.router, prefix="/api")


@app.get("/api/health")
async def health_check():
    return {"status": "ok", "service": "ignisia26"}


if __name__ == "__main__":
    import os
    import uvicorn
    # Lets you start the server by just running this file (Run ▶ button).
    # HOST/PORT are overridable so the same entrypoint works in containers.
    uvicorn.run(
        app,
        host=os.getenv("HOST", "127.0.0.1"),
        port=int(os.getenv("PORT", "8000")),
    )
