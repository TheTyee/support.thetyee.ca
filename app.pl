#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/local/lib/perl5";

use Mojolicious::Lite;
use Mojo::UserAgent;
use Data::Dumper;
use Mojo::Util qw(b64_encode url_escape url_unescape hmac_sha1_sum);
use Mojo::URL;
use Try::Tiny;
use Support::Schema;

my $config = plugin 'JSONConfig';

plugin 'Util::RandomString' => {
    entropy   => 256,
    printable => {
        alphabet => '2345679bdfhmnprtFGHJLMNPRT',
        length   => 20
    }
};

my $ua         = Mojo::UserAgent->new;
my $url        = Mojo::URL->new;
my $subdomain  = $config->{'subdomain'};
my $domain     = $subdomain . '.recurly.com/v2/';
my $apikey     = $config->{'apikey'};
my $privatekey = $config->{'privatekey'};
my $API        = 'https://' . $apikey . ':@' . $domain;

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

helper recurly_get_signature => sub {
    my $self    = shift;
    my $options = shift;
    $url->query( %$options );
    my $query     = $url->query->to_string;
    my $nonce     = $self->random_string;
    my $timestamp = time();
    my $protected_str
        = $query . '&timestamp=' . $timestamp . '&nonce=' . $nonce;
    my $escaped     = $protected_str;
    my $checksum    = hmac_sha1_sum $escaped, $privatekey;
    my $recurly_sig = "$checksum|$escaped";
    return $recurly_sig;
};

helper recurly_get_plans => sub {
    my $self   = shift;
    my $filter = shift;
    my $res = $ua->get( $API . '/plans/' => { Accept => 'application/xml' } )
        ->res;
    my $xml      = $res->body;
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
        my $onetime = $self->param( 'onetime' );
        my $amount  = $self->param( 'amount' );
        my $campaign
            = $self->param( 'campaign' ) || $self->flash( 'campaign' );
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
        my $amount_in_cents;
        if ( $amount ) {
            $amount_in_cents = $amount * 100;
        }
        my $options = {    # RecurlyJS signature options
            'transaction[currency]'        => 'CAD',
            'transaction[amount_in_cents]' => $amount_in_cents,
            'transaction[description]' =>
                'Support for fact-based independent journalism at The Tyee',
        };
        my $recurly_sig = $self->recurly_get_signature( $options );
        my $plans       = $self->recurly_get_plans(
            $config->{'recurly_get_plans_filter'} );
        $self->stash(
            {   plans         => $plans,
                plans_onetime => $config->{'plans_onetime'},
                amount        => $amount,
                onetime       => $onetime || $self->flash( 'onetime' ),
                recurly_sig   => $recurly_sig,
                error         => $self->flash( 'error' ),
            }
        );
        $self->flash( campaign => $campaign );
    };

    any [qw(GET POST)] => '/' => sub {
        my $self = shift;
        $self->stash(
            body_id     => 'voices',
        );
        $self->flash(
            appeal_code => 'voices'
        );
    } => 'voices';

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
        $self->flash(
            appeal_code => 'election2015'
        );
        say Dumper( $self->flash( 'appeal_code' ));
    } => 'election2015';
    any [qw(GET POST)] => '/voices' => sub {
        my $self = shift;
        $self->stash(
            body_id     => 'voices',
            appeal_code => 'voices'
        );
        $self->flash(
            appeal_code => 'voices'
        );
        say Dumper( $self->flash( 'appeal_code' ));
    } => 'voices';
};

post '/successful_transaction' => sub {
    my $self          = shift;
    my $campaign      = $self->flash( 'campaign' );
    my $appeal_code   = $self->flash( 'appeal_code' );
    my $recurly_token = $self->param( 'recurly_token' );
    say Dumper( $appeal_code );
    # Request object from Recurly based on token
    my $res
        = $ua->get( $API
            . '/recurly_js/result/'
            . $recurly_token => { Accept => 'application/xml' } )->res;
    my $xml = $res->body;
    my $dom = Mojo::DOM->new( $xml );
    my $account_code
        = $self->recurly_get_account_code( $dom->at( 'account' ) );
    my $account      = $self->recurly_get_account_details( $account_code );
    my $billing_info = $self->recurly_get_billing_details( $account_code );
    my $transaction_details = {
        email              => $account->at( 'email' )->text,
        first_name         => $account->at( 'first_name' )->text,
        last_name          => $account->at( 'last_name' )->text,
        hosted_login_token => $account->at( 'hosted_login_token' )->text,
        trans_date         => $dom->at( 'created_at' )
        ? $dom->at( 'created_at' )->text
        : $dom->at( 'activated_at' ) ? $dom->at( 'activated_at' )->text
        : '',
        city            => $billing_info->at( 'city' )->text,
        state           => $billing_info->at( 'state' )->text,
        country         => $billing_info->at( 'country' )->text,
        zip             => $billing_info->at( 'zip' )->text,
        amount_in_cents => $dom->at( 'unit_amount_in_cents' )->text,
        plan_name => $dom->at( 'plan name' ) ? $dom->at( 'plan name' )->text
        : '',
        plan_code => $dom->at( 'plan plan_code' )
        ? $dom->at( 'plan plan_code' )->text
        : '',
        campaign   => $campaign,
        appeal_code => $appeal_code,
        user_agent => $self->req->headers->user_agent,
    };
    my $result = $self->find_or_new( $transaction_details );
    $transaction_details->{'id'} = $result->id;
    $self->flash( { transaction_details => $transaction_details, } );
    $self->redirect_to( 'preferences' );
} => 'success';

any [qw(GET POST)] => '/preferences' => sub {
    my $self   = shift;
    my $record = $self->flash( 'transaction_details' );
    $self->stash( { record => $record, } );
    $self->flash( { transaction_details => $record } );

    if ( $self->req->method eq 'POST' && $record ) {    # Submitted form
            # Validate parameters with custom check
        my $validation = $self->validation;
        $validation->required( 'pref_frequency' );
        $validation->required( 'pref_anonymous' );

        # Render form again if validation failed
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
