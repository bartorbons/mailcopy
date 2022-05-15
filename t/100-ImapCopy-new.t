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

can_ok($package, "new");

my $imapcopy = ImapCopy->new(
    from             => $from,
    to               => $to,
    prefix           => $prefix,
    folder_separator => $folder_separator,
    debug            => $debug
);
isa_ok($imapcopy, $package, "Correctly create package");

my $ic2 = ImapCopy->new(
    from             => $from,
    to               => $to,
    prefix           => $prefix,
    folder_separator => $folder_separator,
    debug            => $debug,
    diff             => \{},
    from_message_ids => \{},
    to_message_ids   => \{}
);
isa_ok($ic2, $package, "Correctly create package also with option arguments");

throws_ok(
    sub { my $im2 = ImapCopy->new(
            from             => $from,
            to               => $to,
            prefix           => $prefix,
            folder_separator => $folder_separator,
        );
    },
    qr/required attribute 'debug' missing for class creation/,
    "new with lacking required args fails"
);

throws_ok(
    sub { my $im2 = ImapCopy->new(
            from             => $from,
            to               => $to,
            prefix           => $prefix,
            folder_separator => $folder_separator,
            debug            => 1,
            extra_arg        => "somevalue" 
        );
    },
    qr/unexpected attribute 'extra_arg' for class creation/,
    "new with extra unallowed args fails"
);

done_testing();
