#!/usr/bin/env perl

use Support::Schema;

use Modern::Perl '2013';
use Mojolicious::Lite;
use Mojo::UserAgent;
use Mojo::DOM;
use utf8::all;
use Try::Tiny;
use Data::Dumper;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use POSIX qw(strftime);
use Time::Piece;

# Get the configuration
my $mode = $ARGV[0];
my $config = plugin 'JSONConfig' => { file => "../app.$mode.json" };
say $mode;

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
        if ( $record->wc_response )
        {    # We got back a subscriber ID, so we're good.
                # Mark the record as processed.
            $record->wc_status( 1 );
                        app->log->debug("success from Mailchipm maybe: Here's the response" . $record->wc_response);

        } else {
            app->log->debug("error getting subscriber record back here's the response: " . $record->wc_response);
        }

        # Commit the update so far
        $record->update;

        if ( $record->wc_status == 1 ) {

            # Send a one-off message to new contributors
            # assuming we have the information we need
            # disabling this check
            # my $data_check = _check_subscriber_details( $record->wc_response );
            # if ( $data_check && !$record->wc_send_response )
            #{    # Only those not already e-mailed
                say "We're going to send a message to subscriber: "
                    . $record->email
                    . ' (Subscriber ID: '
                    . $record->wc_response . ')';

               my $wc_send_response = _send_message( $record );
                $record->wc_send_response( $wc_send_response );
                $record->update;
            # } always sending
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
    my $fifteenth_year_mailme = $record->fifteenth_year_mailme // '';
    my $email        = $record->email;
    say "email attempt is $email";
    my $first        = $record->first_name;
    my $last         = $record->last_name;
    my $date         = $record->trans_date;
    say "date is $date";
      my $t = Time::Piece->strptime($date, "%Y-%m-%dT%H:%M:%S");
         my $mctime = $t->strftime("%m/%d/%Y");
   $date = $mctime;   
   
    my $national     = 1;
    my $newspriority = $record->pref_newspriority // '';
    my $level        = $record->amount_in_cents / 100;
    my $plan         = $record->plan_code // '';
    my $hosted_login_token = $record->hosted_login_token;
    my $appeal_code  = $record->appeal_code;
    my $onetime      = '';
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
#	app->log->debug("now searching for email : $email \n");

    # Get the subscriber record, if there is one already

#keeping args for whatcounts even though not sent.. for later if needed    
    my $update_or_sub = {
        %args,

        # If we found a subscriber, it's an update, if not a subscribe
        cmd => $search ? 'update' : 'sub',
        list_id               => $wc_list_id,
        override_confirmation => '1',
        force_sub             => '1',
        format                => '2',
        identity_field        => 'email',
        data =>
            "email,fax,custom_fifteenth_year_mailme,first,last,custom_builder_sub_date,custom_builder,$frequency,custom_builder_regular,custom_builder_onetime,custom_builder_national_newspriority,custom_builder_level,custom_builder_plan,custom_builder_is_anonymous,custom_builder_hosted_login_token,custom_builder_appeal,custom_pref_tyeenews_casl,custom_pref_sponsor_casl^$email,cohort_skip,$fifteenth_year_mailme,$first,$last,$date,1,1,$national,$onetime,$newspriority,$level,$plan,$anon,$hosted_login_token,$appeal_code,1,1"
    };
    
     my $lcemail    = lc $email;
   my $md5email = md5_hex ($lcemail); 
  

my $ub = Mojo::UserAgent->new;

my $merge_fields = {
    APPEAL => $appeal_code,
    FNAME => $first,
    LNAME => $last,
    MMERGE13 => $anon,
    B_HOSTED_L => $hosted_login_token,
    P_T_CASL => 1
};

if ($onetime) {
$merge_fields->{'ONETIME_DT'} = $date;
$merge_fields->{'B_ONE_AMT'} = $level;
$merge_fields->{'B_ONETIME'} = $onetime;
} else {
   $merge_fields->{'B_LEVEL'} = $level;
   $merge_fields->{'B_PLAN'} = $plan;
   $merge_fields->{'B_SUB_DATE'} = $date;
   $merge_fields->{'B_L_T_DATE'} = $date;

}
    
my $interests = {};

if ($frequency =~ /national/) { $interests -> {'34d456542c'} = \1 ; $merge_fields->{'P_S_CASL'} = 1 };
if ($frequency =~ /daily/)  { $interests -> {'e96d6919a3'} = \1 ; $merge_fields->{'P_S_CASL'} = 1};
if ($frequency =~ /national/) {$interests -> {'7056e4ff8d'} = \1; $merge_fields->{'P_S_CASL'} = 1 };

$interests -> {'3f212bb109'} = \1 ;
$interests -> {'5c17ad7674'} = \1 ;

# add to both casl specila newsletter prefs by default
$email = lc $email;
my $errorText;
    # Post it to Mailchimp
    my $args = {
        email_address   => $email,
        status =>       => 'subscribed',
        status_if_new => 'subscribed',
        merge_fields => $merge_fields,
        interests => $interests
    };
    
        my $URL = Mojo::URL->new('https://Bryan:' . $config->{"mc_key"} . '@us14.api.mailchimp.com/3.0/lists/' . $config->{"mc_listid"} . '/members/' . $md5email);
    my $tx = $ua->put( $URL => json => $args );
    my $js = $tx->result->json;
     app->log->debug( "code" . $tx->res->code);
   app->log->debug( Dumper( $js));
   

    
   # my $tx = $ua->post( $API => form => $update_or_sub );
#    if ( my $res = $tx->success ) {
#        $result = $res->body;
#        app->log->debug("success updating or subbing body result:" . $result);    
#
#    }
 #   else {
#        my ( $err, $code ) = $tx->error;
#        $result = $code ? "$code response: $err" : "Connection error: $err";
#    app->log->debug("failure updating record or subbing: $err  $result");    

#}

# check params at https://docs.mojolicious.org/Mojo/Transaction/HTTP
  
 
       


# For some reason, WhatCounts doesn't return the subscriber ID on creation, so we search again.
 if ($tx->res->code == 200 )
   {     
   
        app->log->debug( "unique email id" .  $js->{'unique_email_id'});



    # Just the subscriber ID please!
   # $result =~ s/^(?<subscriber_id>\d+?)\s.*/$+{'subscriber_id'}/gi;
   # chomp( $result );
    $result = $tx->result->body;
        # Output response when debugging
      #          app->log->debug( Dumper( $tx  ) );
      #  app->log->debug( Dumper( $result ) );
            if ( $result =~ 'subscribed' ) {
            my $subscriberID = $js->{'unique_email_id'};
            return $subscriberID;
             }
        
    } else {
        my ( $err, $code ) = $tx->error;
        $result = $code ? "$code response: $err" : "Connection error: " . $err->{'message'};
        # TODO this needs to notify us of a problem
        app->log->debug( Dumper( $result ) );
        # Send a 500 back to the request, along with a helpful message
            $errorText = "error: "  . "status: " .  $js->{'status'} . " title: " .  $js->{'title'};
	app->log->info( $errorText) unless $email eq 'api@thetyee.ca';
            app->log->debug("error: "  . $errorText);
           return ($errorText);

    }
   
}

sub _send_message {
    my $record = shift;
    my $result;
    my $amount_in_cents = $record->amount_in_cents;
    my $amount = $amount_in_cents / 100;
    my $plan_code = $record->plan_code;
    my $hosted_login_token = $record->hosted_login_token;
    my $perks = $record->pref_lapel;
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
        # template_id => '1190',
        # template_id => '1684',
        template_id => '3182', # New 2021 template with perks info
        data        => "amount,plan_code,hosted_login_token,perks^$amount,$plan_code,$hosted_login_token,$perks"
    }; 
 
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
