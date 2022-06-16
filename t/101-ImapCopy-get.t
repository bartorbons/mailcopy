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

my $expect = {
    from             => $from,
    to               => $to,
    prefix           => $prefix,
    folder_separator => $folder_separator,
    debug            => $debug,
};

use_ok($package);

can_ok($package, "get");

my $imapcopy = ImapCopy->new(
    from             => $from,
    to               => $to,
    prefix           => $prefix,
    folder_separator => $folder_separator,
    debug            => $debug
);

foreach my $key (keys %$expect) {
    my $res = $imapcopy->get($key);
    is($res, $expect->{$key}, "key $key has expected value");
}

throws_ok(
    sub { my $res =$imapcopy->get("someatt") },
    qr/unknown key 'someatt' for class/,
    "get for an unknown attribute fails"
);


done_testing();
