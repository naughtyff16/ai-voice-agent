-- =================================================================
-- Migration 084 (Phase 5F.7): language-aware full-text search
-- down_revision: 083_5F6
-- Transaction: yes
-- Source: Phase 5L Global Database Reconciliation, Section 8
--         (multilingual knowledge search — India-first: Tamil, English,
--         Telugu, Hindi)
--
-- knowledge.update_chunk_tsvector() (034_5F.sql) hard-codes
-- to_tsvector('english', content). Stock PostgreSQL ships no stemming
-- dictionary for Tamil/Telugu/Hindi; forcing the 'english' text-search
-- configuration onto them does not error, it silently mis-tokenizes
-- (English stopword removal / stemming rules applied to non-English
-- text), which is exactly the "corrupt/lose keyword discoverability"
-- failure mode this section must avoid.
--
-- Minimal, non-framework fix: a content_language column (source of
-- truth on documents, denormalized onto document_chunks the same way
-- knowledge_base_id already is) selects between PostgreSQL's 'english'
-- configuration for English content and 'simple' (tokenize + lowercase,
-- no stemming, no stopword list) for Tamil/Telugu/Hindi and any
-- Tamil-English code-mixed content. 'simple' is the documented-safe
-- fallback for a language with no dedicated dictionary — it cannot drop
-- or corrupt tokens, which is the one hard requirement in scope. No
-- language-detection logic and no new schema framework are added.
-- =================================================================

ALTER TABLE knowledge.documents
  ADD COLUMN content_language TEXT NOT NULL DEFAULT 'en';
ALTER TABLE knowledge.documents
  ADD CONSTRAINT chk_doc_content_language CHECK (content_language IN ('en','ta','te','hi'));

ALTER TABLE knowledge.document_chunks
  ADD COLUMN content_language TEXT NOT NULL DEFAULT 'en';
ALTER TABLE knowledge.document_chunks
  ADD CONSTRAINT chk_dc_content_language CHECK (content_language IN ('en','ta','te','hi'));

CREATE OR REPLACE FUNCTION knowledge.update_chunk_tsvector()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.tsvector_content := to_tsvector(
    (CASE WHEN NEW.content_language = 'en' THEN 'english' ELSE 'simple' END)::regconfig,
    COALESCE(NEW.content, '')
  );
  RETURN NEW;
END;
$$;
-- CREATE OR REPLACE preserves the existing trg_dc_tsvector BEFORE INSERT
-- trigger binding (038_5F.sql) — no trigger DDL change needed.

COMMENT ON COLUMN knowledge.documents.content_language IS 'Source-of-truth document language (India-first V1 set: en/ta/te/hi). Propagated onto document_chunks.content_language at ingestion time; selects the text-search configuration used by trg_dc_tsvector.';
COMMENT ON COLUMN knowledge.document_chunks.content_language IS 'Denormalized from documents.content_language at ingestion time (worker-supplied, same trust level as the rest of chunk ingestion). Drives to_tsvector() configuration choice in update_chunk_tsvector().';
