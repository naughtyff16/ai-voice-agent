-- =================================================================
-- Migration 082 (Phase 5F.5): KB-wide document-content dedup
-- down_revision: 081_5F4
-- Transaction: yes
-- Source: Phase 5L Global Database Reconciliation, DEP-6F-14
--
-- 4E DDD invariant 1 ("ContentHash ... a document with the same hash in
-- the same Knowledge Base is rejected") and policy NoDuplicateDocument-
-- Content are unambiguously KB-scoped. The executed uq_dv_content_hash
-- (036_5F.sql) is (document_id, content_hash) — document_versions has no
-- knowledge_base_id column at all, so two different documents in the
-- same KB with identical content are not rejected by anything today.
--
-- Design: denormalize knowledge_base_id onto document_versions, but
-- never trust a client/app-supplied value for it — a BEFORE INSERT
-- trigger derives it server-side from the parent document (with a
-- tenant-ownership check), the same anti-spoofing posture used
-- throughout this schema. Existing rows (if any) are backfilled the
-- same way. A same-schema FK enforces it can never drift from its
-- parent afterwards (the column is immutable — see the extended
-- trigger below). The old document-scoped unique index is replaced
-- with a KB-scoped one; a preflight duplicate check runs first and
-- raises (never silently deletes) if any existing data would violate
-- the new constraint.
-- =================================================================

-- 1. Add the column nullable first (safe for any existing rows).
ALTER TABLE knowledge.document_versions
  ADD COLUMN knowledge_base_id UUID NULL;

-- 2. Backfill from the parent document.
UPDATE knowledge.document_versions dv
SET knowledge_base_id = d.knowledge_base_id
FROM knowledge.documents d
WHERE dv.document_id = d.id;

-- 3. Preflight: fail loudly (do not delete data) if backfilling produced
--    any duplicate active content hash within a KB — this would make
--    the new unique index impossible to create.
DO $$
DECLARE
  v_dupe_count INTEGER;
BEGIN
  SELECT count(*) INTO v_dupe_count FROM (
    SELECT knowledge_base_id, content_hash
    FROM knowledge.document_versions
    WHERE status NOT IN ('FAILED','GDPR_ERASED')
    GROUP BY knowledge_base_id, content_hash
    HAVING count(*) > 1
  ) dupes;
  IF v_dupe_count > 0 THEN
    RAISE EXCEPTION 'migration 082_5F5: % existing (knowledge_base_id, content_hash) duplicate group(s) among non-FAILED/GDPR_ERASED document_versions would violate the new KB-wide dedup constraint. Manual reconciliation required before this migration can proceed — see DEP-6F-14.', v_dupe_count;
  END IF;
END;
$$;

-- 4. Tighten: NOT NULL, then FK to the owning knowledge_base.
ALTER TABLE knowledge.document_versions
  ALTER COLUMN knowledge_base_id SET NOT NULL;
ALTER TABLE knowledge.document_versions
  ADD CONSTRAINT fk_dv_kb FOREIGN KEY (knowledge_base_id)
    REFERENCES knowledge.knowledge_bases(id) ON DELETE RESTRICT;

-- 5. Server-derive on every future INSERT — never trust a caller-supplied
--    value. Also re-validates document/tenant ownership as a second,
--    independent check beyond RLS.
CREATE OR REPLACE FUNCTION knowledge.fn_dv_derive_kb_id()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_kb_id UUID;
BEGIN
  SELECT knowledge_base_id INTO v_kb_id
  FROM knowledge.documents
  WHERE id = NEW.document_id AND organization_id = NEW.organization_id;

  IF v_kb_id IS NULL THEN
    RAISE EXCEPTION 'fn_dv_derive_kb_id: document % not found or not owned by tenant %.', NEW.document_id, NEW.organization_id;
  END IF;

  NEW.knowledge_base_id := v_kb_id;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_dv_derive_kb_id
  BEFORE INSERT ON knowledge.document_versions
  FOR EACH ROW EXECUTE FUNCTION knowledge.fn_dv_derive_kb_id();

-- 6. Extend the existing immutable-fields trigger so knowledge_base_id
--    can never drift after insert (it tracks document_id, which is
--    already immutable — this closes the same door for the derived
--    denormalization).
CREATE OR REPLACE FUNCTION knowledge.prevent_docver_immutable_field_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.document_id IS DISTINCT FROM NEW.document_id OR
     OLD.knowledge_base_id IS DISTINCT FROM NEW.knowledge_base_id OR
     OLD.version_number IS DISTINCT FROM NEW.version_number OR
     OLD.mime_type IS DISTINCT FROM NEW.mime_type OR
     OLD.size_bytes IS DISTINCT FROM NEW.size_bytes OR
     OLD.created_at IS DISTINCT FROM NEW.created_at OR
     OLD.created_by IS DISTINCT FROM NEW.created_by THEN
    RAISE EXCEPTION 'document_versions identity/content fields are immutable. version_id: %', OLD.id;
  END IF;
  IF (OLD.storage_ref IS DISTINCT FROM NEW.storage_ref AND NEW.storage_ref != 'ERASED') OR
     (OLD.content_hash IS DISTINCT FROM NEW.content_hash AND NEW.content_hash != 'ERASED') THEN
    RAISE EXCEPTION 'document_versions.storage_ref/content_hash are immutable except for GDPR erasure. version_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- 7. Replace the document-scoped dedup index with the KB-scoped one.
--    KB-scope is a superset guarantee of the old document-scope
--    (uniqueness across the whole KB implies uniqueness within any one
--    document in it), so dropping the old index loses no coverage.
DROP INDEX knowledge.uq_dv_content_hash;
CREATE UNIQUE INDEX uq_dv_content_hash_kb ON knowledge.document_versions (knowledge_base_id, content_hash)
  WHERE status NOT IN ('FAILED','GDPR_ERASED');
CREATE INDEX idx_dv_kb_status ON knowledge.document_versions (knowledge_base_id, status);
