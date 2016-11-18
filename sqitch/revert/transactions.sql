-- Deploy transactions
-- requires: schema

BEGIN;

    SET client_min_messages = 'warning';
    
    ALTER TABLE support.transactions DROP COLUMN payment_type TEXT NULL;
    ALTER TABLE support.transactions DROP COLUMN transit_number TEXT NULL;
    ALTER TABLE support.transactions DROP COLUMN bank_number TEXT NULL;
    ALTER TABLE support.transactions DROP COLUMN account_number TEXT NULL;
    ALTER TABLE support.transactions DROP COLUMN person TEXT NULL;
    ALTER TABLE support.transactions DROP COLUMN referrer TEXT NULL;
    ALTER TABLE support.transactions DROP COLUMN on_behalf_of TEXT NULL;
    ALTER TABLE support.transactions DROP COLUMN on_behalf_of_name TEXT NULL;

COMMIT;
