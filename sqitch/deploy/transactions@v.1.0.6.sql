-- Deploy transactions
-- requires: schema

BEGIN;

    SET client_min_messages = 'warning';
    
    ALTER TABLE support.transactions ADD COLUMN hosted_login_token TEXT NULL;

COMMIT;
