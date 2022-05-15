#!/usr/bin/perl

use strict;
use warnings;

use lib "../lib";

use Test::MockObject;
use Test::More;
use Test::Exception;
use Data::Dumper;

my $package = "ImapCopy";

my $from = Test::MockObject->new()->set_isa("Net::IMAP::Client");
my $to = Test::MockObject->new()->set_isa("Net::IMAP::Client");
my $prefix = 'string';
my $folder_separator = '/';
my $debug = 1;


use_ok($package);

can_ok($package, "log");

my $imapcopy = ImapCopy->new(
    from             => $from,
    to               => $to,
    prefix           => $prefix,
    folder_separator => $folder_separator,
    debug            => $debug
);
isa_ok($imapcopy, $package, "Correctly create package");

foreach my $db (0,1,2,3) {
    $imapcopy->set("debug", $db);
    foreach my $log (1,2,3) {
        my $res = $imapcopy->log($log, "test log level $log, at debug level $db\n");
        is($res, 1, "printed something") if ($log <=$db);
        is($res,"", "not printed anything") if ($log > $db);
    }
}

done_testing();
