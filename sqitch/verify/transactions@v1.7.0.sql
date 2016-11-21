-- Verify transactions

BEGIN;

        SELECT id, email, first_name, last_name, trans_date, amount_in_cents, plan_name, plan_code, city, state, zip, country, 
        pref_anonymous, pref_frequency, pref_newspriority, wc_status, wc_response, user_agent, wc_send_response, 
        hosted_login_token, appeal_code,pref_lapel
    FROM support.transactions
    WHERE false;

ROLLBACK;
