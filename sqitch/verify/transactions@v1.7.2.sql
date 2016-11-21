-- Verify transactions

BEGIN;

        SELECT id, email, first_name, last_name, trans_date, amount_in_cents, plan_name, plan_code, city, state, zip, country, 
        pref_anonymous, pref_frequency, pref_newspriority, wc_status, wc_response, user_agent, wc_send_response, 
        hosted_login_token, appeal_code,pref_lapel,payment_type,phone,transit_number,bank_number,account_number,raiser,referrer,on_behalf_of,on_behalf_of_name_first, on_behalf_of_name_last
    FROM support.transactions
    WHERE false;

ROLLBACK;
