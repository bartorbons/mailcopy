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
my $from = Test::MockObject->new();
$from->set_true("select","status","noop");
$from->set_isa("Net::IMAP::Client");

my $prefix = 'string';
my $folder_separator = '/';
my $debug = 1;


use_ok($package);

can_ok($package, "read_to_imap_folder");

note "Sunny day test";
{
    my $to = Test::MockObject->new();
    my @folders = ("$prefix.folder1", "$prefix.fldr");
    $to->set_list("folders", @folders);
    $to->set_always("select", 1)->set_always("status", 1)->set_always("noop", 1);
    $to->set_always("search", [1, 2]);
    $to->set_series("get_summaries", [$summary1], [$summary2]);
    $to->set_isa("Net::IMAP::Client");
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    isa_ok($imapcopy, $package, "Correctly create package");

    my $res    = $imapcopy->read_to_imap_folder($to, "$prefix.fldr", $from);
    my $expect = {
        '1' => 'message1',
        '2' => 'message2'
    };
    is_deeply($res, $expect, "the return value is as expected");
}

note "Sunny day test, empty folder";
{
    my $to = Test::MockObject->new();
    my @folders = ("$prefix.folder1", "$prefix.fldr");
    $to->set_list("folders", @folders);
    $to->set_always("select", 1)->set_always("status", 1)->set_always("noop", 1);
    $to->set_always("search", []);
    $to->set_series("get_summaries", [$summary1], [$summary2]);
    $to->set_isa("Net::IMAP::Client");
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    my $res    = $imapcopy->read_to_imap_folder($to, "$prefix.fldr", $from);
    my $expect = {};
    is_deeply($res, $expect, "the return value is as expected");
}

note "Sunny day test, with folder creation";
{
    my $to = Test::MockObject->new();
    my @folders = ("$prefix.folder1", "$prefix.otherfolder");
    $to->set_list("folders", @folders);
    $to->set_always("create_folder", 1);
    $to->set_always("select", 1)->set_always("status", 1)->set_always("noop", 1);
    $to->set_always("search", [1, 2]);
    $to->set_series("get_summaries", [$summary1], [$summary2]);
    $to->set_isa("Net::IMAP::Client");
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    isa_ok($imapcopy, $package, "Correctly create package");

    my $res    = $imapcopy->read_to_imap_folder($to, "$prefix.fldr", $from);
    my $expect = {
        '1' => 'message1',
        '2' => 'message2'
    };
    is_deeply($res, $expect, "the return value is as expected");
}

note "Fail test, Weird result from get_summaries";
{
    my $to = Test::MockObject->new();
    my @folders = ("$prefix.folder1", "$prefix.fldr");
    $to->set_list("folders", @folders);
    $to->set_always("select", 1)->set_always("status", 1)->set_always("noop", 1);
    $to->set_always("search", [1, 2]);
    $to->set_series("get_summaries", [$summary1, $summary2], [$summary2]);
    $to->set_isa("Net::IMAP::Client");
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    throws_ok(
        sub { my $res = $imapcopy->read_to_imap_folder($to, "$prefix.fldr", $from); }
        ,
        qr/multiple records returned, unexpected/,
        "error in get_summaries gives a die"
    );
}

done_testing();
