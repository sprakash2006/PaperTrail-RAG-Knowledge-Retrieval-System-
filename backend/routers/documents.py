
import os
import tempfile
from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Form
from dependencies import get_current_user
from services.rag_service import get_rag_service
from services.supabase_client import get_admin_client
from engine.rag_ingestor import FileIngestor

router = APIRouter(prefix="/documents", tags=["documents"])
ingestor = FileIngestor()

ALLOWED_TYPES = {".pdf", ".docx", ".xlsx", ".csv", ".txt", ".eml"}


@router.post("/upload")
async def upload_document(
    file: UploadFile = File(...),
    visibility: str = Form("shared"),
    user: dict = Depends(get_current_user),
):
    ext = os.path.splitext(file.filename)[1].lower()
    if ext not in ALLOWED_TYPES:
        raise HTTPException(status_code=400, detail=f"Unsupported file type: {ext}")

    if visibility not in ("shared", "private"):
        raise HTTPException(status_code=400, detail="visibility must be 'shared' or 'private'")

    content = await file.read()
    tmp_path = os.path.join(tempfile.gettempdir(), file.filename)
    with open(tmp_path, "wb") as f:
        f.write(content)

    try:
        chunks, filename = ingestor.process_file(tmp_path)
        if not chunks:
            raise HTTPException(status_code=422, detail="No content could be extracted from the file")

        sb = get_admin_client()
        storage_path = f"{user['org_id']}/{user['id']}/{file.filename}"
        sb.storage.from_("documents").upload(storage_path, content)

        rag = get_rag_service()
        owner_id = user["id"] if visibility == "private" else None
        result = await rag.ingest_document(
            org_id=user["org_id"],
            owner_id=owner_id,
            filename=file.filename,
            file_type=ext.lstrip("."),
            file_size=len(content),
            chunks=chunks,
            visibility=visibility,
            source_type="upload",
            storage_path=storage_path,
        )

        sb.table("audit_log").insert({
            "org_id": user["org_id"],
            "user_id": user["id"],
            "action": "upload",
            "details": {
                "filename": file.filename,
                "visibility": visibility,
                "chunk_count": result["chunk_count"],
            },
        }).execute()

        return {
            "message": f"Document '{file.filename}' uploaded and indexed successfully",
            "document_id": result["document_id"],
            "chunk_count": result["chunk_count"],
            "visibility": visibility,
        }

    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass


@router.get("/")
async def list_documents(user: dict = Depends(get_current_user)):
    rag = get_rag_service()
    docs = await rag.list_documents(user["org_id"], user["id"])
    return docs


@router.delete("/{document_id}")
async def delete_document(document_id: str, user: dict = Depends(get_current_user)):
    sb = get_admin_client()

    doc = sb.table("documents").select("*").eq("id", document_id).single().execute()
    if not doc.data:
        raise HTTPException(status_code=404, detail="Document not found")

    is_owner = doc.data["owner_id"] is not None and doc.data["owner_id"] == user["id"]
    is_director = user["role"] == "director"
    is_uploader_shared = doc.data["owner_id"] is None
    if not (is_owner or is_director or is_uploader_shared):
        raise HTTPException(status_code=403, detail="Only the owner or a director can delete this document")

    if doc.data.get("storage_path"):
        try:
            sb.storage.from_("documents").remove([doc.data["storage_path"]])
        except Exception:
            pass

    rag = get_rag_service()
    await rag.delete_document(document_id)

    sb.table("audit_log").insert({
        "org_id": user["org_id"],
        "user_id": user["id"],
        "action": "delete",
        "details": {"filename": doc.data["filename"], "document_id": document_id},
    }).execute()

    return {"message": f"Document '{doc.data['filename']}' deleted"}
