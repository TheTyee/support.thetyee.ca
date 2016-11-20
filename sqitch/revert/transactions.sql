-- Deploy transactions
-- requires: schema

BEGIN;

    SET client_min_messages = 'warning';
    
    ALTER TABLE support.transactions DROP COLUMN payment_type;
    ALTER TABLE support.transactions DROP COLUMN phone;
    ALTER TABLE support.transactions DROP COLUMN transit_number;
    ALTER TABLE support.transactions DROP COLUMN bank_number;
    ALTER TABLE support.transactions DROP COLUMN account_number;
    ALTER TABLE support.transactions DROP COLUMN raiser;
    ALTER TABLE support.transactions DROP COLUMN referrer;
    ALTER TABLE support.transactions DROP COLUMN on_behalf_of;
    ALTER TABLE support.transactions DROP COLUMN on_behalf_of_name_first;
    ALTER TABLE support.transactions DROP COLUMN on_behalf_of_name_first;

COMMIT;
