-- Deploy transactions
-- requires: schema

BEGIN;

    SET client_min_messages = 'warning';
    
    ALTER TABLE support.transactions ADD COLUMN address1 TEXT NULL;

COMMIT;
