-- Deploy transactions
-- requires: schema

BEGIN;

    SET client_min_messages = 'warning';
    
    ALTER TABLE support.transactions ADD COLUMN pref_lapel TEXT NULL;

COMMIT;
