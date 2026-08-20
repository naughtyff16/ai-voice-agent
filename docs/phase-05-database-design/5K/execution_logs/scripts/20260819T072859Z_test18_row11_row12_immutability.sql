SET app.tenant_id = '00000000-0000-0000-0000-00000000aaaa';

\echo '-- row 11: UPDATE session_ref on an ACTIVE execution (expect Denied via trg_we_immutable) --'
UPDATE workflow.workflow_executions
SET session_ref = '22222222-2222-2222-2222-222222222222'
WHERE id = '01a018de-91f8-7f5b-ad13-13283e60adc0';

\echo '-- setup: transition execution to COMPLETED (legitimate update, expect success) --'
UPDATE workflow.workflow_executions
SET status = 'COMPLETED', completed_at = now()
WHERE id = '01a018de-91f8-7f5b-ad13-13283e60adc0';

\echo '-- row 12: UPDATE status back to ACTIVE on a COMPLETED row (expect Denied via trg_we_immutable) --'
UPDATE workflow.workflow_executions
SET status = 'ACTIVE'
WHERE id = '01a018de-91f8-7f5b-ad13-13283e60adc0';
