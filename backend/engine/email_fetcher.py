
import os
import imaplib
import email as email_lib
import email.policy
import tempfile
import logging
from email.utils import parsedate_to_datetime
from engine.rag_ingestor import FileIngestor

logger = logging.getLogger(__name__)


class EmailFetcher:
    def __init__(self):
        self.imap_server = os.getenv("EMAIL_IMAP_SERVER", "")
        self.email_addr = os.getenv("EMAIL_ADDRESS", "")
        self.email_pass = os.getenv("EMAIL_PASSWORD", "")
        self.folder = os.getenv("EMAIL_FOLDER", "INBOX")
        self.ingestor = FileIngestor()
        self._seen_ids: set[str] = set()

    def is_configured(self) -> bool:
        return bool(self.imap_server and self.email_addr and self.email_pass)

    def reload_config(self):
        self.imap_server = os.getenv("EMAIL_IMAP_SERVER", "")
        self.email_addr = os.getenv("EMAIL_ADDRESS", "")
        self.email_pass = os.getenv("EMAIL_PASSWORD", "")
        self.folder = os.getenv("EMAIL_FOLDER", "INBOX")

    def fetch_new_emails(self) -> list[dict]:
        if not self.is_configured():
            return []

        results = []
        conn = None

        try:
            conn = imaplib.IMAP4_SSL(self.imap_server)
            conn.login(self.email_addr, self.email_pass)
            conn.select(self.folder, readonly=False)

            status, msg_nums = conn.search(None, "UNSEEN")
            if status != "OK" or not msg_nums[0]:
                return []

            email_ids = msg_nums[0].split()
            logger.info(f"Found {len(email_ids)} unseen email(s)")

            for eid in email_ids:
                try:
                    status, data = conn.fetch(eid, "(RFC822)")
                    if status != "OK" or not data[0]:
                        continue

                    raw_bytes = data[0][1]
                    msg = email_lib.message_from_bytes(
                        raw_bytes, policy=email_lib.policy.default
                    )

                    msg_id = msg.get("Message-ID", "")
                    if msg_id and msg_id in self._seen_ids:
                        continue
                    if msg_id:
                        self._seen_ids.add(msg_id)

                    subject = str(msg.get("Subject", "(No Subject)"))
                    sender = str(msg.get("From", "Unknown"))
                    email_date = None
                    raw_date = msg.get("Date")
                    if raw_date:
                        try:
                            dt = parsedate_to_datetime(str(raw_date))
                            email_date = dt.strftime("%Y-%m-%d")
                        except Exception:
                            pass

                    safe_id = (msg_id or str(eid)).replace("<", "").replace(">", "")
                    safe_id = "".join(c if c.isalnum() else "_" for c in safe_id)[:60]
                    eml_filename = f"email_{safe_id}.eml"
                    tmp_path = os.path.join(tempfile.gettempdir(), eml_filename)

                    with open(tmp_path, "wb") as f:
                        f.write(raw_bytes)

                    chunks, _ = self.ingestor.process_file(tmp_path)

                    try:
                        os.remove(tmp_path)
                    except OSError:
                        pass

                    if chunks:
                        results.append({
                            "filename": eml_filename,
                            "subject": subject,
                            "from": sender,
                            "date": email_date or "unknown",
                            "chunks": chunks,
                        })

                    conn.store(eid, "+FLAGS", "\\Seen")

                except Exception as e:
                    logger.error(f"Failed to process email {eid}: {e}")
                    continue

        except imaplib.IMAP4.error as e:
            logger.error(f"IMAP error: {e}")
        except Exception as e:
            logger.error(f"Email fetch failed: {e}")
        finally:
            if conn:
                try:
                    conn.close()
                    conn.logout()
                except Exception:
                    pass

        return results

    def test_connection(self) -> tuple[bool, str]:
        if not self.is_configured():
            return False, "IMAP credentials not configured in .env"

        try:
            conn = imaplib.IMAP4_SSL(self.imap_server)
            conn.login(self.email_addr, self.email_pass)
            status, folders = conn.list()
            conn.logout()
            return True, f"Connected to {self.imap_server} as {self.email_addr}"
        except imaplib.IMAP4.error as e:
            return False, f"IMAP auth failed: {e}"
        except Exception as e:
            return False, f"Connection failed: {e}"
