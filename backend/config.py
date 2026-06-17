
import os
from dotenv import load_dotenv

load_dotenv()


class Settings:
    SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
    SUPABASE_ANON_KEY: str = os.getenv("SUPABASE_ANON_KEY", "")
    SUPABASE_SERVICE_ROLE_KEY: str = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
    OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")

    # Comma-separated list of allowed CORS origins (frontend URLs).
    # Defaults to the local Vite/React dev servers.
    CORS_ORIGINS: list[str] = [
        o.strip()
        for o in os.getenv(
            "CORS_ORIGINS", "http://localhost:5173,http://localhost:3000"
        ).split(",")
        if o.strip()
    ]

    EMBEDDING_MODEL: str = "all-MiniLM-L6-v2"
    EMBEDDING_DIM: int = 384

    TOP_K: int = 15
    MATCH_THRESHOLD: float = 0.3

    LLM_MODEL: str = "gpt-4o"
    LLM_CONFLICT_MODEL: str = "gpt-4o-mini"
    LLM_TEMPERATURE: float = 0.2
    LLM_MAX_TOKENS: int = 2000


settings = Settings()
