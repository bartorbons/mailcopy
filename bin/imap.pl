#!/usr/bin/perl 

use strict;
use warnings;
use lib "./lib";

use Config::File qw(read_config_file);
use Data::Dumper;
use IO::Socket::SSL;
use Net::IMAP::Client;
use ImapCopy;

my $config_file = shift;
my $config = read_config_file($config_file) || die "could not read configfile $config_file\n";

my $debug = $config->{debug};

#setting up connecting to the servers etc...
print "going to connect to imapserver (fromhost)\n" if ($debug ==3);
my $from_socket = IO::Socket::SSL->new(
    PeerAddr    => $config->{fromhost},
    PeerPort    => 993,
    Proto       => 'tcp'
) || die "connecting from_host: error=$!, ssl_error=$SSL_ERROR";
print "connected to imapserver (fromhost)\n" if ($debug >=2);

print "going to connect to imap server (tohost)\n" if ($debug ==3);
my $to_socket = IO::Socket::SSL->new(
    PeerAddr    => $config->{tohost},
    PeerPort    => 993,
    SSL_ca_file => $config->{to_SSL_ca_file},
    Proto       => 'tcp'
) || die "connecting to_host: error=$!, ssl_error=$SSL_ERROR";
print "connected to imap server (tohost)\n" if ($debug >=2);


my $from_imap = Net::IMAP::Client->new(
    DEBUG   => 1,
    TIMEOUT => 2,
    socket  => $from_socket,
);
print "Going to authenticate at from-imap server\n" if ($debug ==3);
my $from_res = $from_imap->login($config->{fromusername},$config->{frompassword});
if (!$from_res) {
    die $from_imap->last_error();
} else {
    print "Succesfully authenticated and connected to imap server (from_server)\n" if ($debug >=2);
}

my $to_imap = Net::IMAP::Client->new(
    DEBUG   => 1,
    TIMEOUT => 2,
    socket  => $to_socket,
);

print "Going to authenticate at imap server (to-server)\n" if ($debug ==3);
my $to_res = $to_imap->login($config->{tousername},$config->{topassword});
if (!$to_res) {
    die $to_imap->last_error();
} else {
    print "Succesfully authenticated and connected to imap server (to_server)\n" if ($debug >=2);
}

my $fseperator = $from_imap->separator();

my $imc = ImapCopy->new(
    from             => $from_imap,
    to               => $to_imap,
    debug            => $debug,
    prefix           => $config->{prefix},
    folder_separator => $fseperator
);

$imc->run();

exit;

