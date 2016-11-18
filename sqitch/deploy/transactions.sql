-- Deploy transactions
-- requires: schema

BEGIN;

    SET client_min_messages = 'warning';
    
    ALTER TABLE support.transactions ADD COLUMN payment_type TEXT NULL;
    ALTER TABLE support.transactions ADD COLUMN phone TEXT NULL;
    ALTER TABLE support.transactions ADD COLUMN transit_number TEXT NULL;
    ALTER TABLE support.transactions ADD COLUMN bank_number TEXT NULL;
    ALTER TABLE support.transactions ADD COLUMN account_number TEXT NULL;
    ALTER TABLE support.transactions ADD COLUMN person TEXT NULL;
    ALTER TABLE support.transactions ADD COLUMN referrer TEXT NULL;
    ALTER TABLE support.transactions ADD COLUMN on_behalf_of TEXT NULL;
    ALTER TABLE support.transactions ADD COLUMN on_behalf_of_name TEXT NULL;

COMMIT;
