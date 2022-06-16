#!/usr/bin/perl

use strict;
use warnings;

use lib "../lib";

use Test::MockObject;
use Test::More;
use Test::Exception;

my $package = "ImapCopy";

my $from = Test::MockObject->new();
$from->set_always("select", 1);
$from->set_always("status", 1);
$from->set_always(
    "get_summaries",
    [
        {internaldate => "2022-01-01T12:00:01.12+0100"},
    ]
);
$from->set_always("get_rfc822_body", "Message body");
$from->set_always("get_flags", "data");
$from->set_isa("Net::IMAP::Client");
my $to = Test::MockObject->new();
$to->set_always("select", 1);
$to->set_always("status", 1);
$to->set_always("append", 1);
$to->set_isa("Net::IMAP::Client");
my $prefix = 'string';
my $folder_separator = '/';
my $debug = 1;


use_ok($package);

can_ok($package, "copy_remaining");

note "copy one message";
{
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    my $diff = { 'message3' => 3 };

    my $to_folder = "tofolder";
    my $from_folder = "fromfolder";
    my $expect = 1;
    my $res = $imapcopy->copy_remaining($from, $to, $from_folder, $to_folder, $diff);
    is_deeply($res, $expect, "expected result");
}

note "no messages to copy";
{
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    my $diff = { };

    my $to_folder = "tofolder";
    my $from_folder = "fromfolder";
    my $expect = 0;
    my $res = $imapcopy->copy_remaining($from, $to, $from_folder, $to_folder, $diff);

    is_deeply($res, $expect, "expected result");
}

note "4 messages to copy";
{
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    my $diff = { 'message1' => 1, 'message2' => 2, 'message3' => 3, 'message4' => 4 };

    my $to_folder = "tofolder";
    my $from_folder = "fromfolder";
    my $expect = 4;
    my $res = $imapcopy->copy_remaining($from, $to, $from_folder, $to_folder, $diff);

    is_deeply($res, $expect, "expected result");
}

note "twisted diff test";
{
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    my $diff = { 'message1' => 1, 'message2' => 2, 'message3' => 3, 'message4' => 1 };

    my $to_folder = "tofolder";
    my $from_folder = "fromfolder";
    my $expect = 3;
    my $res = $imapcopy->copy_remaining($from, $to, $from_folder, $to_folder, $diff);

    is_deeply($res, $expect, "expected result");
}


done_testing();
