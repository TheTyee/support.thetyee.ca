#!/usr/bin/env perl

use Support::Schema;

use Modern::Perl '2013';
use Mojolicious::Lite;
use Mojo::UserAgent;
use Mojo::DOM;
use utf8::all;
use Try::Tiny;
use Data::Dumper;

# Get the configuration
my $mode = $ARGV[0];
my $config = plugin 'JSONConfig' => { file => "../app.$mode.json" };

# Get a UserAgent
my $ua = Mojo::UserAgent->new;

# WhatCounts setup
my $API        = $config->{'wc_api_url'};
my $wc_list_id = $config->{'wc_listid'};
my $wc_realm   = $config->{'wc_realm'};
my $wc_pw      = $config->{'wc_password'};

main();

#-------------------------------------------------------------------------------
#  Subroutines
#-------------------------------------------------------------------------------
sub main {
    my $dbh     = _dbh();
    my $records = _get_records( $dbh );
    _process_records( $records );
}

sub _dbh {
    my $schema = Support::Schema->connect( $config->{'pg_dsn'},
        $config->{'pg_user'}, $config->{'pg_pass'}, );
    return $schema;
}

sub _get_records
{    # Get only records that have not been processed from the database
    my $schema     = shift;
    my $to_process = $schema->resultset( 'Transaction' )->search(
        {    # Not undef, not processed
            wc_status => [ undef, { '!=', 1 } ]
        }
    );
    return $to_process;
}

sub _process_records {    # Process each record
    my $to_process = shift;
    while ( my $record = $to_process->next ) {
        my $wc_response;
        my $frequency = _determine_frequency( $record->pref_frequency );

        # _determine_frequency will always return a frequency here,
        # because we want all records to be stored in WhatCounts
        $wc_response = _create_or_update( $record, $frequency );
        $record->wc_response( $wc_response );
        if ( $record->wc_response =~ /^\d+$/ )
        {    # We got back a subscriber ID, so we're good.
                # Mark the record as processed.
            $record->wc_status( 1 );
        } else {
                    app->log->debug("error " . $record->wc_response);
        }

        # Commit the update so far
        $record->update;

        if ( $record->wc_status == 1 ) {

            # Send a one-off message to new contributors
            # assuming we have the information we need
            my $data_check
                = _check_subscriber_details( $record->wc_response );
            if ( $data_check && !$record->wc_send_response )
            {    # Only those not already e-mailed
                say "We're going to send a message to subscriber: "
                    . $record->email
                    . ' (Subscriber ID: '
                    . $record->wc_response . ')';

                my $wc_send_response = _send_message( $record );
                $record->wc_send_response( $wc_send_response );
                $record->update;
            }
        }
    }
}

#-------------------------------------------------------------------------------
#  Subroutines
#-------------------------------------------------------------------------------
sub _determine_frequency
{    # Niave way to determine the subscription preference, if any
    my $subscription = shift;
    my $frequency;
    if ( defined $subscription && $subscription =~ /weekly/i ) {
        $frequency = 'custom_pref_enews_weekly';
    }
    elsif ( defined $subscription && $subscription =~ /daily/i ) {
        $frequency = 'custom_pref_enews_daily';
    }   
	 elsif ( defined $subscription && $subscription =~ /national/i ) {
        $frequency = 'custom_pref_enews_national';
    }
    else {    # This is used to ensure the record gets added to WhatCounts
        $frequency = 'custom_pref_enews_nochoice';
    }
    return $frequency;
}

sub _get_subscriber_details {
    my $subscriber_id = shift;

    # Get the subscriber details as XML
    my $search;
    my $result;
    my %args = (
        r => $wc_realm,
        p => $wc_pw,
    );
    my $search_args = {
        %args,
        c             => 'detail',
        subscriber_id => $subscriber_id,
        output_format => 'xml',
        header        => 1,
    };

    # Get the subscriber record, if there is one already
    my $s = $ua->post( $API => form => $search_args );
    if ( my $res = $s->success ) {
        $result = $res->body;
    }
    else {
        my ( $err, $code ) = $s->error;
        $result = $code ? "$code response: $err" : "Connection error: $err";
    }
    return $result;
}

sub _check_subscriber_details {
    my $subscriber_id  = shift;
    my $subscriber_xml = _get_subscriber_details( $subscriber_id );

    # use Mojo::Dom to parse the XML
    my $dom = Mojo::DOM->new( $subscriber_xml );

    # check for builder_amount, builder_onetime, etc.
    my $builder_level         = $dom->at( 'builder_level' );
    my $hosted_login_token    = $dom->at( 'builder_hosted_login_token' );
    #my $builder_national_2013 = $dom->at( 'builder_national_2013' );
    if ( $builder_level && $hosted_login_token ) {

        # Return 1 for good, 0 for bad.
        return 1;
    }
    else {
        return 0;
    }
}

sub _create_or_update {   # Post the vitals to WhatCounts, return the resposne
    my $record       = shift;
    my $frequency    = shift;
    my   $fifteenth_year_mailme = $record->fifteenth_year_mailme // '';
    my $email        = $record->email;
    my $first        = $record->first_name;
    my $last         = $record->last_name;
    my $date         = $record->trans_date;
    my $national     = 1;
    my $newspriority = $record->pref_newspriority // '';
    my $level        = $record->amount_in_cents / 100;
    my $plan         = $record->plan_code // '';
    my $hosted_login_token = $record->hosted_login_token;
    my $appeal_code  = $record->appeal_code;
    my $onetime      = '';
    
                        say "fiteenth_year_mailme = " . $fifteenth_year_mailme;

    
    if ( !$record->plan_name ) {
        $onetime = 1;
    }
    my $anon;
    if ( defined $record->pref_anonymous && $record->pref_anonymous eq 'Yes' )
    {
        $anon = 0;
    }
    else {
        $anon = 1;
    }
    my $search;
    my $result;
    my %args = (
        r => $wc_realm,
        p => $wc_pw,
    );
    my $search_args = {
        %args,
        cmd   => 'find',
        email => $email,
    };

    # Get the subscriber record, if there is one already
    my $s = $ua->post( $API => form => $search_args );
    if ( my $res = $s->success ) {
        $search = $res->body;
    }
    else {
        my ( $err, $code ) = $s->error;
        $result = $code ? "$code response: $err" : "Connection error: $err";
    }
    my $update_or_sub = {
        %args,

        # If we found a subscriber, it's an update, if not a subscribe
        cmd => $search ? 'update' : 'sub',
        list_id               => $wc_list_id,
        override_confirmation => '1',
        force_sub             => '1',
        format                => '2',
        data =>
            "email,fax,custom_fifteenth_year_mailme,first,last,custom_builder_sub_date,custom_builder,$frequency,custom_builder_regular,custom_builder_onetime,custom_builder_national_newspriority,custom_builder_level,custom_builder_plan,custom_builder_is_anonymous,custom_builder_hosted_login_token,custom_builder_appeal,custom_pref_tyeenews_casl,custom_pref_sponsor_casl^$email,'cohort_skip',$fifteenth_year_mailme,$first,$last,$date,1,1,$national,$onetime,$newspriority,$level,$plan,$anon,$hosted_login_token,$appeal_code,1,1"
    };
    
    say Dumper($update_or_sub);
    my $tx = $ua->post( $API => form => $update_or_sub );
    if ( my $res = $tx->success ) {
        $result = $res->body;
    }
    else {
        my ( $err, $code ) = $tx->error;
        $result = $code ? "$code response: $err" : "Connection error: $err";
    }

# For some reason, WhatCounts doesn't return the subscriber ID on creation, so we search again.
    if ( $result =~ /SUCCESS/ ) {
        my $r = $ua->post( $API => form => $search_args );
        if ( my $res = $r->success ) { $result = $res->body }
        else {
            my ( $err, $code ) = $r->error;
            $result
                = $code ? "$code response: $err" : "Connection error: $err";
        }
    }

    # Just the subscriber ID please!
    $result =~ s/^(?<subscriber_id>\d+?)\s.*/$+{'subscriber_id'}/gi;
    chomp( $result );
    return $result;
}

sub _send_message {
    my $record = shift;
    my $result;
    my $amount_in_cents = $record->amount_in_cents;
    my $amount = $amount_in_cents / 100;
    my $plan_code = $record->plan_code;
    my $hosted_login_token = $record->hosted_login_token;
    my %wc_args = (
        r         => $wc_realm,
        p         => $wc_pw,
        c         => 'send',
        list_id   => $wc_list_id,
        format    => 99,
        force_sub => 1,
    );
    
    
    my $message_args = {
        %wc_args,
        to          => $record->email,
        from        => '"The Tyee" <builders@thetyee.ca>',
        charset     => 'ISO-8859-1',
        template_id => '1190',
#        template_id => '1684',
        data        => "amount,plan_code,hosted_login_token^$amount,$plan_code,$hosted_login_token"
    };

    
    if (  (!$plan_code && $amount >= 75)  || ($plan_code && $amount >=15 )  ){
        $message_args->{'template_id'} = '1684';
        say "amount is larger than 75 one-time or 15 monthly for " . $record->email;
    } else {
        say "amount is smaller than 75 one timeor 15 monthly, normal message " . $record->email;
    }
 
 
 
    
    # Get the subscriber record, if there is one already
    my $s = $ua->post( $API => form => $message_args );
    if ( my $res = $s->success ) {
        $result = $res->body;
    }
    else {
        my ( $err, $code ) = $s->error;
        $result = $code ? "$code response: $err" : "Connection error: $err";
    }
    return $result;
}
