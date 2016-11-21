#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/local/lib/perl5";

use Mojolicious::Lite;
use Mojo::UserAgent;
use Data::Dumper;
use DateTime;
use Mojo::Util qw(b64_encode url_escape url_unescape hmac_sha1_sum);
use Mojo::URL;
use Try::Tiny;
use Support::Schema;
use XML::Mini::Document;

my $config = plugin 'JSONConfig';

plugin 'Util::RandomString' => {
    entropy   => 256,
    printable => {
        alphabet => '2345679bdfhmnprtFGHJLMNPRT',
        length   => 20
    }
};

my $ua        = Mojo::UserAgent->new;
my $url       = Mojo::URL->new;
my $subdomain = $config->{'subdomain'};
my $domain    = $subdomain . '.recurly.com/v2/';
my $apikey    = $config->{'privatekey'};
my $API       = 'https://' . $apikey . ':@' . $domain;

helper schema => sub {
    my $schema = Support::Schema->connect( $config->{'pg_dsn'},
        $config->{'pg_user'}, $config->{'pg_pass'}, );
    return $schema;
};

helper find_or_new => sub {
    my $self = shift;
    my $doc  = shift;
    my $dbh  = $self->schema();
    my $result;
    try {
        $result = $dbh->txn_do(
            sub {
                my $rs = $dbh->resultset( 'Transaction' )
                    ->find_or_new( {%$doc} );
                unless ( $rs->in_storage ) {
                    $rs->insert;
                }
                return $rs;
            }
        );
    }
    catch {
        $self->app->log->warn( $_ );
    };
    return $result;
};

helper recurly_get_plans => sub {
    my $self   = shift;
    my $filter = shift;
    my $res = $ua->get( $API . '/plans/' => { Accept => 'application/xml' } )
        ->res;
    my $xml = $res->body;
    my $dom      = Mojo::DOM->new( $xml );
    my $plans    = $dom->find( 'plan' );
    my $filtered = [];
    foreach my $plan ( $plans->each ) {    # iterate the Collection object
        next unless $plan->plan_code->text =~ /$filter/;
        push @$filtered, $plan;
    }
    @$filtered = sort {
        $a->unit_amount_in_cents->CAD->text <=>
            $b->unit_amount_in_cents->CAD->text
    } @$filtered;
    return $filtered;
};

helper recurly_get_account_code => sub {
    my $self         = shift;
    my $account      = shift;
    my $account_href = $account->{'href'};
    my $account_code = $account_href;
    $account_code =~ s!https://$subdomain\.recurly\.com/v2/accounts/!!;
    return $account_code;
};

helper recurly_get_account_details => sub {
    my $self         = shift;
    my $account_code = shift;
    my $res
        = $ua->get( $API
            . '/accounts/'
            . $account_code => { Accept => 'application/xml' } )->res;
    my $xml = $res->body;
    my $dom = Mojo::DOM->new( $xml );
    return $dom;
};

helper recurly_get_billing_details => sub {
    my $self         = shift;
    my $account_code = shift;
    my $res
        = $ua->get( $API
            . '/accounts/'
            . $account_code
            . '/billing_info' => { Accept => 'application/xml' } )->res;
    my $xml = $res->body;
    my $dom = Mojo::DOM->new( $xml );
    return $dom;
};

group {
    under [qw(GET POST)] => '/' => sub {
        my $self    = shift;
        # Store the referrer once in the flash
        my $referrer = $self->req->headers->referrer;
        if ( !$self->flash('original_referrer') ) {
            $self->flash( original_referrer => $referrer );
        }
        # Store the campaign-tracking value
        my $campaign
            = $self->param( 'campaign' ) || $self->flash( 'campaign' );
        $self->flash( campaign => $campaign );
        # TODO remove these two
        my $onetime = $self->param( 'onetime' );
        my $amount  = $self->param( 'amount' );
        # TODO remove this statement
        if ( $self->req->method eq 'POST' && $amount =~ /\D/ ) {
            $self->flash(
                {   error    => 'Amount needs to be a whole number',
                    onetime  => 'onetime',
                    campaign => $campaign,
                }
            );
            $self->param( { amount => '0' } );
            $amount = '';
            $self->redirect_to( '' );
        }
        # TODO remove
        my $amount_in_cents;
        if ( $amount ) {
            $amount_in_cents = $amount * 100;
        }
        # TODO remove this hash
        my $options = {    # RecurlyJS signature options
            'transaction[currency]'        => 'CAD',
            'transaction[amount_in_cents]' => $amount_in_cents,
            'transaction[description]' =>
                'Support for fact-based independent journalism at The Tyee',
        };

        my $plans = $self->recurly_get_plans(
            $config->{'recurly_get_plans_filter'} );
        $self->stash(
            {   plans         => $plans,
                plans_onetime => $config->{'plans_onetime'},
                amount        => $amount,
                onetime       => $onetime || $self->flash( 'onetime' ),
                error => $self->flash( 'error' ),
            }
        );
    };

    any [qw(GET POST)] => '/' => sub {
        my $self = shift;
        $self->stash( body_id => 'powermap', );
        $self->flash( appeal_code => 'powermap' );
    } => 'powermap';

    any [qw(GET POST)] => '/powermap' => sub {
        my $self = shift;
        $self->stash(
            body_id     => 'powermap',
            appeal_code => 'powermap'
        );
    } => 'powermap';

    any [qw(GET POST)] => '/builders' => sub {
        my $self = shift;
        $self->stash(
            body_id     => 'builders',
            appeal_code => 'builders'
        );
    } => 'builders';

    any [qw(GET POST)] => '/national' => sub {
        my $self = shift;
        $self->stash(
            body_id     => 'national',
            appeal_code => 'national'
        );
    } => 'national';
    any [qw(GET POST)] => '/evergreen' => sub {
        my $self = shift;
        $self->stash(
            body_id     => 'evergreen',
            appeal_code => 'evergreen'
        );
    } => 'evergreen';
    any [qw(GET POST)] => '/election2015' => sub {
        my $self = shift;
        $self->stash(
            body_id     => 'election2015',
            appeal_code => 'election2015'
        );
        $self->flash( appeal_code => 'election2015' );
    } => 'election2015';
    any [qw(GET POST)] => '/voices' => sub {
        my $self = shift;
        $self->stash(
            body_id     => 'voices',
            appeal_code => 'voices'
        );
        $self->flash( appeal_code => 'voices' );
    } => 'voices';
};

# New route for processing EFT/ACH subscriptions
any [qw(GET POST)] => '/process_bank' => sub {
    my $self   = shift;
    my $params = $self->flash( 'params' );
    my $campaign        = $self->flash( 'campaign' );
    my $appeal_code     = $self->flash( 'appeal_code' );
    my $referrer     = $self->flash( 'original_referrer' );
    my $dt              = DateTime->now;
    $dt->set_time_zone( 'Europe/London' );
    my $trans_date = $dt->ymd . ' ' . $dt->hms;
    my $states     = $params->{'state'};
    # There are two possible state values, but only one should be used
    my $state = @$states[0] ? @$states[0] : @$states[1];
    my $transaction_details = {
        email              => $params->{'email'},
        phone              => $params->{'phone'},
        first_name         => $params->{'first-name'},
        last_name          => $params->{'last-name'},
        hosted_login_token => 'Bank transaction. Not applicable',
        trans_date         => $trans_date,                        # Add a date
        address1               => $params->{'address1'},
        city               => $params->{'city'},
        state              => $state,
        country            => $params->{'country'},
        zip                => $params->{'postal-code'},
        amount_in_cents    => $params->{'amount-in-cents'},
        plan_name          => $params->{'plan-name'},
        plan_code          => $params->{'plan'},
        payment_type       => $params->{'payment-type'},
        transit_number     => $params->{'transit-number'},
        bank_number        => $params->{'bank-number'},
        account_number     => $params->{'account-number'},
        campaign           => $campaign,
        appeal_code        => $appeal_code,
        referrer           => $referrer,
        user_agent         => $self->req->headers->user_agent,
    };
    my $result = $self->find_or_new( $transaction_details );
    $transaction_details->{'id'} = $result->id;
    $self->flash( { transaction_details => $transaction_details, } );
    $self->redirect_to( 'preferences' );
};

# New route for processing the form post with the upgraded Recurly.js
# Take the token, plus the plan, and send a post to the Recurly Subscrptions API
# post '/process_transaction
post '/process_transaction' => sub {
    my $self         = shift;
    # Capture values from flash
    my $campaign     = $self->flash( 'campaign' );
    my $appeal_code  = $self->flash( 'appeal_code' );
    my $referrer     = $self->flash( 'original_referrer' );
    my $payment_type = $self->param( 'payment-type' );
    my $token        = $self->param( 'recurly-token' );
    my $plan         = $self->param( 'plan' );
    # TODO remove $amount
    my $amount       = $self->param( 'amount' );
    my $amount_in_cents  = $self->param( 'amount-in-cents' );
    my $first_name   = $self->param( 'first-name' );
    my $last_name    = $self->param( 'last-name' );
    my $address      = $self->param( 'address1' );
    my $city         = $self->param( 'city' );
    my $state        = $self->param( 'state' );
    my $country      = $self->param( 'country' );
    my $postal       = $self->param( 'postal-code' );
    my $email        = $self->param( 'email' );
    my $phone        = $self->param( 'phone' );
    my $params       = $self->req->body_params->to_hash;
    if ( $payment_type eq 'bank' ) { # If it's a EFT/ACH, redirect to /process_bank
        $self->flash(
            {   params      => $params,
                campaign    => $campaign,
                appeal_code => $appeal_code,
                original_referrer => $referrer
            }
        );
        $self->redirect_to( 'process_bank' );
        return;
    }

    # Create a new XML document to work with Recurly's APIs
    my $xmldoc = XML::Mini::Document->new();
    # This can be done using a hash:
    my $transaction;
    my $res;
    if ( !$plan && $amount_in_cents ) {    # It's a transaction, not a subscription
        $transaction = {
            'transaction' => {
                'amount_in_cents' => $amount_in_cents,
                'currency'        => 'CAD',
                'account'         => {
                    'account_code' => lc $email,
                    'first_name'   => $first_name,
                    'last_name'    => $last_name,
                    'email'        => lc $email,
                    'billing_info' => { 'token_id' => $token }
                }
            }
        };
        $xmldoc->fromHash( $transaction );
        my $transxml = $xmldoc->toString;
        # Post the XML to the /transacdtions endpoint
        $res
            = $ua->post( $API
                . 'transactions' =>
                { 'Content-Type' => 'application/xml', Accept => '*/*' } =>
                $transxml )->res;
    }
    else {
        $transaction = {    # It's a subscription
            'subscription' => {
                'plan_code' => $plan,
                'currency'  => 'CAD',
                'account'   => {
                    'account_code' => lc $email,
                    'first_name'   => $first_name,
                    'last_name'    => $last_name,
                    'email'        => lc $email,
                    'billing_info' => { 'token_id' => $token }
                }
            }
        };
        $xmldoc->fromHash( $transaction );
        my $transxml = $xmldoc->toString;
        # Post the XML to the /subscriptions endpoint
        $res
            = $ua->post( $API
                . 'subscriptions' =>
                { 'Content-Type' => 'application/xml', Accept => '*/*' } =>
                $transxml )->res;
    }
    my $xml = $res->body;
    say Dumper($xml);
    my $dom = Mojo::DOM->new( $xml );
    if ( $dom->at( 'error' ) ) {    # We got an error message back
        my $error = $dom->at( 'error' )->text;
        $self->flash( { error => $error } );
        $self->redirect_to( '/' );
    }
    else {    # Otherwise, store the transaction and send to /preferences
        my $account_code
            = $self->recurly_get_account_code( $dom->at( 'account' ) );
        my $account = $self->recurly_get_account_details( $account_code );
        my $billing_info
            = $self->recurly_get_billing_details( $account_code );
        my $transaction_details = {
            email => $account->at( 'email' ) ? $account->at( 'email' )->text
            : '',
            first_name => $account->at( 'first_name' )
            ? $account->at( 'first_name' )->text
            : '',
            last_name => $account->at( 'last_name' )
            ? $account->at( 'last_name' )->text
            : '',
            hosted_login_token => $account->at( 'hosted_login_token' )
            ? $account->at( 'hosted_login_token' )->text
            : '',
            trans_date => $dom->at( 'created_at' )
            ? $dom->at( 'created_at' )->text
            : $dom->at( 'activated_at' ) ? $dom->at( 'activated_at' )->text
            : '',
            address1 => $billing_info->at( 'address1' ) ? $billing_info->at( 'address1' )->text : '',
            city => $billing_info->at( 'city' )
            ? $billing_info->at( 'city' )->text
            : '',
            state => $billing_info->at( 'state' )
            ? $billing_info->at( 'state' )->text
            : '',
            country => $billing_info->at( 'country' )
            ? $billing_info->at( 'country' )->text
            : '',
            zip => $billing_info->at( 'zip' )
            ? $billing_info->at( 'zip' )->text
            : '',
            amount_in_cents => $dom->at( 'unit_amount_in_cents' ) ? $dom->at( 'unit_amount_in_cents' )->text : $dom->at( 'amount_in_cents' ) ? $dom->at( 'amount_in_cents' )->text : '',

            # TODO put back in the created date
            plan_name => $dom->at( 'plan name' )
            ? $dom->at( 'plan name' )->text
            : '',
            plan_code => $dom->at( 'plan plan_code' )
            ? $dom->at( 'plan plan_code' )->text
            : '',
            campaign    => $campaign,
            appeal_code => $appeal_code,
            referrer    => $referrer,
            payment_type => $payment_type,
            phone => $phone,
            user_agent  => $self->req->headers->user_agent,
        };
        my $result = $self->find_or_new( $transaction_details );
        $transaction_details->{'id'} = $result->id;
        $self->flash( { transaction_details => $transaction_details, } );
        $self->redirect_to( 'preferences' );
    }
};

any [qw(GET POST)] => '/preferences' => sub {
    my $self   = shift;
    my $record = $self->flash( 'transaction_details' );
    $self->stash( { record => $record, } );
    $self->flash( { transaction_details => $record } );

    if ( $self->req->method eq 'POST' && $record ) {    # Submitted form
        # TODO *actually* validate parameters with custom check
        my $validation = $self->validation;
        $validation->required( 'pref_frequency' );
        $validation->required( 'pref_anonymous' );

        # Render form again if validation failed
        # TODO actually render form again vs. just writing to log
        $self->app->log->info( Dumper $validation ) if $validation->has_error;
        $self->app->log->info( Dumper $self->req->params->to_hash )
            if $validation->has_error;
        #return $self->render( 'preferences' ) if $validation->has_error;

        my $update = $self->find_or_new( $record );
        $update->update( $self->req->params->to_hash );
        $self->flash( { transaction_details => $record } );
        $self->redirect_to( 'share' );
    }
} => 'preferences';

get '/share' => sub {
    my $self                = shift;
    my $transaction_details = $self->flash( 'transaction_details' );
    $self->stash( { transaction_details => $transaction_details } );
    $self->render( 'share' );
} => 'share';

get '/plans' => sub {    # List plans; Not used
    my $self = shift;
    $self->render_not_found;    # Doesn't exist for now
    my $res
        = $ua->get( $API . 'plans' => { Accept => 'application/xml' } )->res;
    my $xml   = $res->body;
    my $dom   = Mojo::DOM->new( $xml );
    my @plans = $dom->find( 'plan' );
    $self->stash( { plans => @plans } );
    $self->render( 'index' );
};

app->secret( $config->{'app_secret'} );
app->start;
