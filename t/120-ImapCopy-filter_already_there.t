#!/usr/bin/perl

use strict;
use warnings;

use lib "../lib";

use Test::MockObject;
use Test::More;
use Test::Exception;

my $package = "ImapCopy";

my $from = Test::MockObject->new()->set_isa("Net::IMAP::Client");
my $to = Test::MockObject->new()->set_isa("Net::IMAP::Client");
my $prefix = 'string';
my $folder_separator = '/';
my $debug = 1;


use_ok($package);

can_ok($package, "filter_already_there");

note "calculate the work to do (lists are equal)";
{
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    my $to_hash = {
        '1' => 'message1',
        '2' => 'message2'
    };
    my $from_hash = {
        'message1' => 1,
        'message2' => 2
    };

    my $res = $imapcopy->filter_already_there($from_hash, $to_hash);
    my $expect = {};
    is_deeply($res, $expect, "expected result");
}

note "calculate the work to do (from list is longer)";
{
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    my $to_hash = {
        '1' => 'message1',
        '2' => 'message2'
    };
    my $from_hash = {
        'message1' => 1,
        'message2' => 2,
        'message3' => 3
    };

    my $res = $imapcopy->filter_already_there($from_hash, $to_hash);
    my $expect = { 'message3' => 3 };
    is_deeply($res, $expect, "expected result");
}

note "calculate the work to do (to list is longer)";
{
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    my $to_hash = {
        '1' => 'message1',
        '2' => 'message2',
        '3' => 'message3'
    };
    my $from_hash = {
        'message1' => 1,
        'message2' => 2,
    };

    my $res = $imapcopy->filter_already_there($from_hash, $to_hash);
    my $expect = { };
    is_deeply($res, $expect, "expected result");
}

note "calculate the work to do (to list is empty)";
{
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    my $to_hash = { };
    my $from_hash = {
        'message1' => 1,
        'message2' => 2,
    };

    my $res = $imapcopy->filter_already_there($from_hash, $to_hash);
    my $expect = { 
        'message1' => 1,
        'message2' => 2,
    };
    is_deeply($res, $expect, "expected result");
}
note "calculate the work to do (from list is empty)";
{
    my $imapcopy = ImapCopy->new(
        from             => $from,
        to               => $to,
        prefix           => $prefix,
        folder_separator => $folder_separator,
        debug            => $debug
    );
    my $to_hash = {
        '1' => 'message1',
        '2' => 'message2'
    };
    my $from_hash = {
    };

    my $res = $imapcopy->filter_already_there($from_hash, $to_hash);
    my $expect = {};
    is_deeply($res, $expect, "expected result");
}

done_testing();
