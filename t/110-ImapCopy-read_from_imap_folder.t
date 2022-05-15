#!/usr/bin/perl

use strict;
use warnings;

use lib "../lib";

use Test::MockObject;
use Test::More;
use Test::Exception;
use Data::Dumper;

my $package = "ImapCopy";

#define the from imap mock object.

my $summary1 = Test::MockObject->new();
$summary1->set_always("message_id", "message1");
$summary1->set_isa('Net::IMAP::Client::MsgSummary');
my $summary2 = Test::MockObject->new();
$summary2->set_always("message_id", "message2");
$summary2->set_isa('Net::IMAP::Client::MsgSummary');
my $broken_summary = Test::MockObject->new();
$broken_summary->set_always("message_id", "");
$broken_summary->set_isa('Net::IMAP::Client::MsgSummary');
my $broken_summary2 = Test::MockObject->new();
$broken_summary2->set_always("message_id", undef);
$broken_summary2->set_isa('Net::IMAP::Client::MsgSummary');

#define the to imap mock object -- Usefull for all the test....
my $to = Test::MockObject->new();
$to->set_true("select","status","noop");
$to->set_isa("Net::IMAP::Client");

my $prefix = 'string';
my $folder_separator = '/';
my $debug = 1;


use_ok($package);

can_ok($package, "read_from_imap_folder");

note "Sunny day test";
{
    my $from = Test::MockObject->new();
    $from->set_always("select", 1)->set_always("status", 1)->set_always("noop", 1);
    $from->set_always("search", [1, 2]);
    $from->set_series("get_summaries", [$summary1], [$summary2]);
    $from->set_isa("Net::IMAP::Client");
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    isa_ok($imapcopy, $package, "Correctly create package");

    my $res    = $imapcopy->read_from_imap_folder($from, "fldr", $to);
    my $expect = {
        'message1' => 1,
        'message2' => 2
    };
    is_deeply($res, $expect, "the return value is as expected");
    is_deeply($imapcopy->get("from_message_ids"),
        $expect, "the internal from-imapfolder-administration is correct");
}

note "Sunny day test, empty folder";
{
    my $from = Test::MockObject->new();
    $from->set_always("select", 1)->set_always("status", 1)->set_always("noop", 1);
    $from->set_always("search", []);
    $from->set_series("get_summaries", [$summary1], [$summary2]);
    $from->set_isa("Net::IMAP::Client");
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    my $res    = $imapcopy->read_from_imap_folder($from, "fldr", $to);
    my $expect = {};
    is_deeply($res, $expect, "the return value is as expected");
    is_deeply($imapcopy->get("from_message_ids"),
        $expect, "the internal from-imapfolder-administration is correct");
}

note "Fail test, Weird result from get_summaries";
{
    my $from = Test::MockObject->new();
    $from->set_always("select", 1)->set_always("status", 1)->set_always("noop", 1);
    $from->set_always("search", [1, 2]);
    $from->set_series("get_summaries", [$summary1, $summary2], [$summary2]);
    $from->set_isa("Net::IMAP::Client");
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    throws_ok(
        sub { my $res = $imapcopy->read_from_imap_folder($from, "fldr", $to); }
        ,
        qr/multiple records returned, unexpected/,
        "error in get_summaries gives a die"
    );
}
note "Fail test, no message_id in message";
{
    my $from = Test::MockObject->new();
    $from->set_always("select", 1)->set_always("status", 1)->set_always("noop", 1);
    $from->set_always("search", [1, 2]);
    $from->set_series("get_summaries", [$summary1], [$broken_summary]);
    $from->set_isa("Net::IMAP::Client");
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    throws_ok(
        sub { my $res = $imapcopy->read_from_imap_folder($from, "fldr", $to); }
        ,
        qr/from imapserver folder fldr, message 2 has no id/,
        "message without messageid gives a die"
    );
}

note "Fail test, empty message_id in message";
{
    my $from = Test::MockObject->new();
    $from->set_always("select", 1)->set_always("status", 1)->set_always("noop", 1);
    $from->set_always("search", [1, 2]);
    $from->set_series("get_summaries", [$broken_summary2]);
    $from->set_isa("Net::IMAP::Client");
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    throws_ok(
        sub { my $res = $imapcopy->read_from_imap_folder($from, "fldr", $to); }
        ,
        qr/from imapserver folder fldr, message 1 has no id/,
        "message without messageid gives a die"
    );
}

done_testing();
