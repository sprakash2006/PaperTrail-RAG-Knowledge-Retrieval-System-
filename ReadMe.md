# Ignisia26 — Enterprise Knowledge Retrieval & Support Platform

> A production-grade **RAG (Retrieval-Augmented Generation)** platform for multi-format
> document intelligence, built around three pillars: **data integrity** (conflict &
> duplicate detection), **role-based access control** (org-hierarchy aware), and
> **grounded, citation-backed answers** (strict anti-hallucination prompting).

Ignisia26 lets an organization upload its documents and emails, ask natural-language
questions across all of them, and get answers that are **only** grounded in those
sources — complete with citations, data-quality warnings, and automatic resolution of
contradictory information. It also includes a full **AI-assisted customer support
ticketing** workflow that drafts and sends resolution emails from the knowledge base.

---

## 📑 Table of Contents

- [System Overview](#-system-overview)
- [Architecture](#-architecture)
- [Feature Reference (Every Feature)](#-feature-reference-every-feature)
  - [1. Multi-Format Document Ingestion](#1-multi-format-document-ingestion)
  - [2. Format-Aware Chunking](#2-format-aware-chunking)
  - [3. Vector Embeddings & Semantic Search](#3-vector-embeddings--semantic-search)
  - [4. Retrieval-Augmented Q&A](#4-retrieval-augmented-qa)
  - [5. Structured, Grounded Answers](#5-structured-grounded-answers)
  - [6. Duplicate Detection](#6-duplicate-detection)
  - [7. Conflict Detection & Resolution](#7-conflict-detection--resolution)
  - [8. Role-Based Access Control (RBAC)](#8-role-based-access-control-rbac)
  - [9. Shared vs. Private Documents](#9-shared-vs-private-documents)
  - [10. Email Integration (IMAP Auto-Ingestion)](#10-email-integration-imap-auto-ingestion)
  - [11. Conversations & Chat History](#11-conversations--chat-history)
  - [12. Customer Support Ticketing](#12-customer-support-ticketing)
  - [13. AI Ticket Resolution & Email Sending](#13-ai-ticket-resolution--email-sending)
  - [14. Audit Logging](#14-audit-logging)
  - [15. Authentication & User Management](#15-authentication--user-management)
  - [16. Document Storage](#16-document-storage)
  - [17. Streamlit Prototype](#17-streamlit-prototype)
- [Tech Stack](#-tech-stack)
- [Project Structure](#-project-structure)
- [Database Schema](#-database-schema)
- [API Reference](#-api-reference)
- [Installation & Setup](#-installation--setup)
- [Environment Variables](#-environment-variables)
- [Running the Application](#-running-the-application)
- [Demo Data](#-demo-data)

---

## 🌐 System Overview

The repository ships **two complementary deployments** that share the same core RAG
engine (`rag_ingestor.py`, `conflict_detector.py`, `email_fetcher.py`):

| Deployment | Stack | Vector Store | Use Case |
|------------|-------|--------------|----------|
| **Production app** | FastAPI + React/Vite + Supabase | Supabase **pgvector** (HNSW) | Multi-tenant, persistent, auth-gated platform |
| **Streamlit prototype** | Streamlit single-file app | **ChromaDB** (local, persisted) | Rapid demo / single-user exploration |

Both share the identical document-processing pipeline and the same structured,
anti-hallucination answer format.

---

## 🏗 Architecture

```
                        ┌──────────────────────────────┐
                        │   React + Vite Frontend       │
                        │  (Auth, Chat, Upload, Email,  │
                        │   Tickets, Dashboard)         │
                        └───────────────┬──────────────┘
                                        │ /api  (Vite proxy → :8000)
                                        ▼
                        ┌──────────────────────────────┐
                        │       FastAPI Backend         │
                        │  auth · documents · chat ·    │
                        │  emails · tickets routers     │
                        └───────┬───────────────┬──────┘
                                │               │
                ┌───────────────▼──┐     ┌──────▼─────────────────┐
                │ Shared RAG Engine │     │   Supabase             │
                │ • FileIngestor    │     │ • Postgres + pgvector  │
                │ • ConflictDetector│     │ • Auth (JWT)           │
                │ • EmailFetcher    │     │ • Storage bucket       │
                │ • Embeddings      │     │ • Row-Level Security   │
                └───────┬───────────┘     │ • match_chunks RPC     │
                        │                 └────────────────────────┘
                        ▼
            ┌────────────────────────┐         ┌─────────────────┐
            │ SentenceTransformer     │         │   OpenAI API    │
            │ all-MiniLM-L6-v2 (384d) │         │ gpt-4o /        │
            └────────────────────────┘         │ gpt-4o-mini     │
                                               └─────────────────┘
```

An interactive architecture diagram is also provided at
[`architecture-diagram.html`](architecture-diagram.html).

---

## ✨ Feature Reference (Every Feature)

### 1. Multi-Format Document Ingestion
Upload and index any combination of:

| Format | Extension | Extractor | Notes |
|--------|-----------|-----------|-------|
| PDF | `.pdf` | `pdfplumber` | Per-page text extraction, page numbers preserved |
| Word | `.docx` | `python-docx` | Paragraph text + heading-based section tracking |
| Excel | `.xlsx` | `openpyxl` | **Row-level** chunking, multi-sheet aware |
| CSV | `.csv` | Python `csv` | **Row-level** chunking with header mapping |
| Plain text | `.txt` | native | Paragraph-based chunking |
| Email | `.eml` | `email` stdlib | Thread-split, header-tagged chunks |

Unsupported file types are safely skipped with a warning, and files that yield no
extractable content return a clear "no content extracted" message instead of failing
silently.

### 2. Format-Aware Chunking
Chunking strategy adapts to the document type to preserve structural meaning:

- **Spreadsheets (XLSX/CSV):** each row becomes one chunk, rendered as
  `[Sheet: X, Row: N] Header: value | Header: value | …`. This keeps each record
  self-describing so the LLM never loses column context. Sheet name is stored as the
  chunk's `section`.
- **PDF:** text is split per page (≤1000 chars/chunk) with page numbers retained for
  citation.
- **DOCX:** paragraphs are combined and split (≤1000 chars), with the most recent
  `Heading`-styled paragraph recorded as the `section`.
- **TXT:** paragraph-aware splitting (`\n\n` boundaries) with overflow handled
  line-by-line.
- **Email:** the body is split on quoted-reply / forwarded-message boundaries
  (`On … wrote:`, `---------- Forwarded message ----------`, `From:…Sent:`), each
  thread part tagged with a `[Email from / To / Subject / Date]` header line.

Every chunk carries metadata: `page`, `line`/`row`, `section`, and `source_date`.

### 3. Vector Embeddings & Semantic Search
- Embeddings generated locally with **`sentence-transformers` `all-MiniLM-L6-v2`**
  (384 dimensions) — no embedding API cost.
- **Production:** vectors stored in Postgres via the **pgvector** extension, indexed
  with **HNSW** (`m=16, ef_construction=64`) using cosine distance. Retrieval is done
  through the `match_chunks` SQL function, which combines similarity search **and**
  access control in a single query.
- **Prototype:** vectors stored in **ChromaDB** (`hnsw:space = cosine`), persisted to a
  local `rag_store/` directory.
- A configurable similarity threshold (`MATCH_THRESHOLD = 0.3`) filters out weak
  matches; `TOP_K` controls how many chunks are retrieved.

### 4. Retrieval-Augmented Q&A
For each question:
1. The query is embedded and the top-K most similar chunks are retrieved (30 candidates
   in the prototype, narrowed to 15).
2. Retrieved chunks are filtered by the asking user's access rights.
3. Chunks are analyzed for duplicates and conflicts.
4. A grounded context block (with source/page/line/section/date tags) is assembled.
5. The LLM (**`gpt-4o`**, temperature 0.2) answers using only that context.
6. Recent conversation history (last 10 messages) is included for follow-up questions.

### 5. Structured, Grounded Answers
Every answer is forced into a **mandatory four-section format**:

1. **✅ Final Answer** — the direct response.
2. **⚠️ Data Quality Notes** — missing values, conflicts, and duplicates (or
   "No data quality issues detected").
3. **🧾 Source References** — file name, page/row, and section for each fact used.
4. **🧠 Reasoning** — what was found, what was missing, how conflicts were resolved.

**Anti-hallucination guardrails:** the system prompt instructs the model to answer
**only** from the provided context, never use outside knowledge, and respond
*"Value not available in the source documents"* when the answer isn't present. Partial
answers must explicitly state what is missing.

### 6. Duplicate Detection
Before answering, retrieved chunks are scanned for **identical content appearing in
multiple sources**. Duplicates are reported to the user (with a text preview and the
list of locations) and passed to the LLM as an advisory so redundancy is noted in the
answer.

### 7. Conflict Detection & Resolution
A two-layer system catches contradictory facts across documents:

- **Heuristic layer** — parses `key: value` segments (especially from spreadsheet rows)
  and flags any field that has **different values across sources**.
- **LLM layer** (`ConflictDetector`, using **`gpt-4o-mini`**, temperature 0) — compares
  cross-source chunk pairs and detects semantic contradictions (e.g. different prices,
  refund windows, deadlines, contact details for the *same* thing), while ignoring
  merely supplementary or differently-worded info.

**Automatic resolution strategy** (`_resolve_conflict`):
1. **Recency wins** — the more recently dated source is trusted.
2. **Source-type priority** when dates tie — structured data ranks highest:
   `xlsx/xls (4) > csv (3) > pdf/docx (2) > txt/eml (1)`.
3. **Fallback** — if neither resolves it, the system flags the conflict for manual
   verification.

Resolved conflicts surface in the UI as warning cards showing the **trusted** vs.
**overridden** source, their dates, and the resolution rationale.

### 8. Role-Based Access Control (RBAC)
Three roles with hierarchical document visibility:

| Role | Can see |
|------|---------|
| **Director** | All documents in the organization |
| **Manager** | Shared docs + own private docs + all (recursive) subordinates' private docs |
| **Employee** | Shared docs + own private docs only |

The org hierarchy is modeled via a self-referencing `reports_to` field. Subordinates
are resolved **recursively** — in production via the `get_all_subordinates` SQL
function, and in the prototype via `org_model.all_subordinates`. Access control is
enforced at **three** levels: the `match_chunks` retrieval query, the document-listing
service, and Supabase **Row-Level Security** policies.

### 9. Shared vs. Private Documents
Every document is either:
- **Shared** (org-wide, `owner_id = NULL`) — visible to everyone in the org.
- **Private** (`owner_id` set) — visible only per the RBAC rules above.

Uploaded emails are always ingested as **private** documents owned by the connecting
user. Deletion is restricted to the document owner or a director.

### 10. Email Integration (IMAP Auto-Ingestion)
- Connect any IMAP mailbox (Gmail, etc.) via server, address, password, and folder.
- **Test connection** endpoint validates credentials before saving.
- **Poll** fetches all `UNSEEN` messages, parses each (including multipart bodies and
  threaded replies), ingests them as private knowledge, and marks them `\Seen`.
- De-duplication via `Message-ID` tracking prevents re-ingesting the same email.
- `last_polled_at` is recorded per user; ingestion events are written to the audit log.
- Per-user email config is stored in the `email_configs` table (one config per user).

### 11. Conversations & Chat History
- Multi-conversation support — create, list (most-recent first), and delete
  conversations.
- Each message (user + assistant) is persisted with its **sources** and **analysis**
  (conflicts/duplicates) as JSONB.
- The last 10 messages of a conversation are fed back into the model for context-aware
  follow-ups.
- Conversations are strictly scoped to their owning user.

### 12. Customer Support Ticketing
A complete support desk built on the same knowledge base:

- **Raise a ticket** — public endpoint (no login required); captures customer name,
  email, phone, subject, query, category, and priority. Logged-in agents are recorded
  as the raiser; anonymous tickets are attributed to the demo org.
- **List & filter** — paginated ticket list (`page`, `per_page`) with optional status
  filter.
- **Stats** — counts by status (`total`, `open`, `in_progress`, `resolved`, `closed`).
- **Assign** — an agent claims a ticket, moving it to `in_progress`.
- **Internal notes** — agents add and list private notes on a ticket
  (`ticket_notes` table).
- Ticket lifecycle: `open → in_progress → resolved → closed`.

### 13. AI Ticket Resolution & Email Sending
When an agent resolves a ticket:
1. The customer's query is run through the **RAG engine** (with conflict/duplicate
   analysis).
2. A second LLM pass (`gpt-4o-mini`) formats the grounded answer into a **professional,
   customer-ready HTML email** — warm greeting by name, clean paragraphs, professional
   sign-off — while **stripping internal sections** (Data Quality Notes, Source
   References, Reasoning).
3. If conflicts were detected, the email is instructed to present **only the
   resolved/latest values** — never expose conflicting internal data to the customer.
4. The agent can **edit the drafted email body** before sending.
5. **Send** delivers the email via SMTP (`smtp.gmail.com:465` SSL), marks the ticket
   `email_sent` + `closed`, and guards against double-sending.

### 14. Audit Logging
Every significant action is recorded in the `audit_log` table with org, user, action
type, JSON details, and timestamp:
- `upload` — filename, visibility, chunk count
- `delete` — filename, document id
- `query` — question, source count, conflict count
- `email_ingest` — count and email metadata

Directors can view all org audit logs; users can view their own.

### 15. Authentication & User Management
- **Signup / Login** via Supabase Auth (JWT). On signup, a Postgres trigger
  (`handle_new_user`) auto-creates the user's `profiles` row with org, name, and role.
- **`/auth/me`** returns the current profile; **PATCH** updates name, `reports_to`, or
  avatar.
- **`/auth/org/members`** lists everyone in the caller's organization.
- Bearer-token auth is enforced on protected routes via the `get_current_user`
  dependency; an `get_optional_user` variant powers the public ticket form.
- Frontend route guards (`ProtectedRoute` / `PublicRoute`) gate pages by auth state.

### 16. Document Storage
Original uploaded files are stored in a private Supabase **Storage** bucket
(`documents`) under an `{org_id}/{user_id}/{filename}` path, with storage-level RLS
policies scoping access to the uploader's organization. Deleting a document also removes
its stored file.

### 17. Streamlit Prototype
The single-file [`app.py`](app.py) provides a self-contained demo of the entire engine:
- Sidebar **user switcher** to act as any of the demo org members and see RBAC in action.
- Drag-and-drop multi-file upload with shared/private toggle.
- Live **email feed** panel with refresh.
- **Indexed documents** list with type/visibility icons and visible-chunk count.
- Chat interface with expandable **source references** and **conflict** cards.
- **Clear all data** button. Backed by ChromaDB and the in-memory `org_model`.

---

## 🧰 Tech Stack

**Backend**
- FastAPI, Uvicorn, Pydantic
- Supabase (Postgres + pgvector + Auth + Storage)
- OpenAI (`gpt-4o`, `gpt-4o-mini`)
- sentence-transformers (`all-MiniLM-L6-v2`)
- pdfplumber, python-docx, openpyxl

**Frontend**
- React 19 + Vite 8
- React Router 7
- `@supabase/supabase-js`
- react-markdown

**Prototype**
- Streamlit
- ChromaDB
- PyMuPDF, pdfplumber, unstructured, NLTK

---

## 📂 Project Structure

```
ignisia26/
├── app.py                      # Streamlit prototype (ChromaDB)
├── main.py                     # Launcher → streamlit run app.py
├── rag_ingestor.py             # FileIngestor — multi-format extraction & chunking
├── rag_retriever.py            # RAGRetriever — ChromaDB search + grounded prompting
├── conflict_detector.py        # ConflictDetector — heuristic + LLM conflict logic
├── email_fetcher.py            # EmailFetcher — IMAP polling & ingestion
├── org_model.py                # In-memory org hierarchy & RBAC (prototype)
├── pdf_utils.py                # PDF page render + highlight (PyMuPDF)
├── check_chunks.py             # Dev script: inspect chunking output
├── test_semantic.py            # Dev script: test semantic chunking
├── requirements.txt            # Prototype dependencies
├── architecture-diagram.html   # Interactive architecture diagram
│
├── backend/                    # Production FastAPI service
│   ├── main.py                 # App + CORS + router wiring + /api/health
│   ├── config.py               # Settings (models, top_k, thresholds)
│   ├── dependencies.py         # JWT auth dependency
│   ├── requirements.txt
│   ├── routers/
│   │   ├── auth.py             # signup, login, me, org members
│   │   ├── documents.py        # upload, list, delete
│   │   ├── chat.py             # conversations, messages, query
│   │   ├── emails.py           # config, test, poll
│   │   └── tickets.py          # raise, list, stats, assign, resolve, send, notes
│   └── services/
│       ├── rag_service.py      # Supabase/pgvector RAG pipeline
│       ├── embedding_service.py# Cached embedding model
│       └── supabase_client.py  # Admin / user client factories
│
├── frontend/                   # React + Vite SPA
│   ├── vite.config.js          # Dev proxy /api → :8000
│   ├── package.json
│   └── src/
│       ├── App.jsx             # Routes + auth guards
│       ├── lib/                # api client, supabase client, AuthContext
│       ├── components/         # Sidebar, Loader
│       └── pages/              # Home, Auth, Dashboard, Upload, Email,
│                               #   RaiseTicket, Tickets, ResolveTicket
│
└── supabase/
    └── migrations/             # Schema, RLS, RPCs, triggers, demo seed data
```

---

## 🗄 Database Schema

Core tables (Postgres / Supabase):

| Table | Purpose |
|-------|---------|
| `organizations` | Tenants (multi-org ready) |
| `profiles` | Users: role, `reports_to`, org — extends `auth.users` |
| `documents` | File metadata: type, size, visibility, source, status |
| `chunks` | Text + `vector(384)` embedding + page/line/section/date |
| `conversations` | Chat threads per user |
| `messages` | Chat messages with `sources` + `analysis` JSONB |
| `email_configs` | Per-user IMAP settings |
| `tickets` | Support tickets + AI response + email body + lifecycle |
| `ticket_notes` | Internal agent notes |
| `audit_log` | All user actions |

**Key database functions:**
- `match_chunks(...)` — cosine-similarity vector search **with built-in RBAC**.
- `get_all_subordinates(manager_id)` — recursive CTE for org-hierarchy visibility.
- `handle_new_user()` — trigger that provisions a profile on signup.
- `update_updated_at()` — timestamp triggers.

**Security:** Row-Level Security is enabled on every table, with policies enforcing
org-scoping, document visibility, conversation ownership, and audit-log access. The HNSW
index on `chunks.embedding` powers fast vector search.

---

## 🔌 API Reference

All routes are prefixed with `/api`. Protected routes require
`Authorization: Bearer <token>`.

**Auth** — `/api/auth`
- `POST /signup`, `POST /login`, `GET /me`, `PATCH /me`, `GET /org/members`

**Documents** — `/api/documents`
- `POST /upload` (multipart; `visibility=shared|private`)
- `GET /` (list accessible), `DELETE /{document_id}`

**Chat** — `/api/chat`
- `POST /conversations`, `GET /conversations`, `DELETE /conversations/{id}`
- `GET /conversations/{id}/messages`
- `POST /query` (the main RAG endpoint)

**Emails** — `/api/emails`
- `POST /config`, `GET /config`, `DELETE /config`
- `POST /test-connection`, `POST /poll`

**Tickets** — `/api/tickets`
- `POST /raise` (public), `GET /` (paginated), `GET /stats`, `GET /{id}`
- `PATCH /{id}/assign`, `POST /{id}/resolve`
- `PATCH /{id}/email-body`, `POST /{id}/send-email`
- `POST /{id}/notes`, `GET /{id}/notes`

**Health** — `GET /api/health`

---

## ⚙️ Installation & Setup

### 1. Clone
```bash
git clone https://github.com/sprakash2006/ignisia26.git
cd ignisia26
```

### 2. Backend (FastAPI)
```bash
python -m venv venv
# Windows
.\venv\Scripts\activate
# macOS/Linux
source venv/bin/activate

pip install -r backend/requirements.txt
```

### 3. Frontend (React)
```bash
cd frontend
npm install
cd ..
```

### 4. Supabase
1. Create a Supabase project and enable the `vector` and `uuid-ossp` extensions.
2. Run the SQL migrations in `supabase/migrations/` **in order** (schema → seed).
3. Grab your project URL, anon key, and service-role key.

### 5. Streamlit prototype (optional)
```bash
pip install -r requirements.txt
```

---

## 🔑 Environment Variables

**Backend** (`.env` in project root or `backend/`):
```env
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
OPENAI_API_KEY=sk-...

# For ticket email sending (SMTP) and prototype email polling:
EMAIL_ADDRESS=you@gmail.com
EMAIL_PASSWORD=your_app_password
```

**Frontend** (`frontend/.env`):
```env
VITE_SUPABASE_URL=https://xxxx.supabase.co
VITE_SUPABASE_ANON_KEY=your_anon_key
```

**Prototype email** (optional, in root `.env`):
```env
EMAIL_IMAP_SERVER=imap.gmail.com
EMAIL_ADDRESS=you@gmail.com
EMAIL_PASSWORD=your_app_password
EMAIL_FOLDER=INBOX
```

> For Gmail, use an [App Password](https://myaccount.google.com/apppasswords), not your
> account password.

---

## ▶️ Running the Application

**Backend** (from `backend/`):
```bash
uvicorn main:app --reload --port 8000
```

**Frontend** (from `frontend/`):
```bash
npm run dev    # Vite dev server on :5173, proxies /api → :8000
```

Then open the Vite URL (default `http://localhost:5173`).

**Streamlit prototype**:
```bash
streamlit run app.py
# or
python main.py
```

---

## 🧪 Demo Data

The seed migrations create a **"Ignisia Demo"** organization with a four-person
hierarchy:

| Name | Role | Reports To |
|------|------|------------|
| Arjun | Director | — |
| Meera | Manager | Arjun |
| Priya | Employee | Meera |
| Rahul | Employee | Meera |

Seed data also includes sample shared/private documents (PDF, DOCX, XLSX, EML — plus
intentionally `processing` and `failed` records to exercise UI states), pre-populated
conversations demonstrating clean answers, a duplicate-detection case, and a
conflict-resolution case, an example email config, and audit-log history. The Streamlit
prototype uses the same four users via `org_model.py` so you can switch identities and
watch RBAC filter results live.

---

*Built for reliable, access-controlled, conflict-aware enterprise knowledge retrieval.*
