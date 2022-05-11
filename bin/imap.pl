#!/usr/bin/perl 

use strict;
use warnings;

use Config::File qw(read_config_file);
use Data::Dumper;
use IO::Socket::SSL;
use Net::IMAP::Client;

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
#done setting up...

#global vars
my %from_message_ids;
my %to_message_ids;

#and get to work:
my @folders = $from_imap->folders();
my $fcounter;

foreach my $folder (@folders) {
    %from_message_ids = ();
    %to_message_ids = ();
    my $folder_repl = $folder;
    $folder_repl =~ s/$fseperator/\./g;
    my $to_folder = $config->{prefix}.".$folder_repl";
    print "Handling folder $folder\n" if ($debug);
    read_from_imap_folder($from_imap, $folder, $to_imap);       #fill the from message_ids.
    print Dumper \%from_message_ids if ($debug ==3);

    read_to_imap_folder($to_imap, $to_folder, $from_imap);        #fill the message_ids already there.
    filter_already_there();                           #filter out the messages already archived
    copy_remaining($from_imap, $to_imap, $folder, $to_folder); #copy what needs to be copied.
    $fcounter++;
}
print "handled $fcounter folders to Mailarchief\n" if ($debug);


##################################################################
##                    read_from_imap_folder                     ##
##                                                              ##
## function that fills the list of potential messages that may  ##
## need to be transfered to the archive mailfolder on the imap  ##
## server. (The to_imap needs to be passed in so that the       ##
## connection to the to_imap server can be kept alive for big   ##
## from-imap folders)                                           ##
##################################################################

sub read_from_imap_folder {
    my $imap = shift;
    my $folder = shift;
    my $to_imap = shift;

    my $select = $imap->select($folder);
    my $status = $imap->status($folder);
    print Dumper $status if ($debug ==3);
    my $from_folder_msgs = $imap->search('ALL');
    my $msgcount = (defined $from_folder_msgs) ? @$from_folder_msgs : 0;
    print "Found $msgcount messages in $folder on from imap server\n" if ($debug >= 2);
    my $teller = 0;
    foreach my $message (@$from_folder_msgs) {
        my $summaries = $imap->get_summaries($message);
        if (scalar @$summaries > 1) {
            die "multiple records returned, unexpected\n";
        }
        my $message_id = $summaries->[0]->message_id;
        $message_id =~ s/^\s+//;
        $message_id =~ s/\s+$//;
        if (!defined $message_id || length($message_id) ==0) {
            die "from imapserver folder $folder, message $message has no id\n";
        }
        print "MessageID $message_id found in $folder on from imap server\n" if ($debug >=2);
        $from_message_ids{$message_id} = $message;
        $teller++;
        if ($teller > 500) {
            my $res = $to_imap->noop; #keep the connection alive;
            print "to_imap kept alive\n" if ($debug ==3);
            $teller = 0;
        }
    }
}

##################################################################
##                     read_to_imap_folder                      ##
##                                                              ##
## function that fills the list of already present messages in  ##
## the archive folder. Those messages do not need to be         ##
## transfered to the imap server. (The from_imap needs to be    ##
## passed in to keep the connection alive for big to_imap       ##
## folders)                                                     ##
##################################################################

sub read_to_imap_folder {
    my $imap = shift;
    my $to_folder = shift;
    my $from_imap = shift;

    my @to_folders = $imap->folders();

    my @folderexists = grep { $_ eq $to_folder } @to_folders;
    if (!@folderexists) {
        my $res = $imap->create_folder($to_folder) or die "Could not create imap folder $to_folder\n";
        print "Folder $to_folder created on mail archive\n" if ($debug);
    } else {
        print "Using existing folder $to_folder\n" if ($debug);
    }

    my $fres = $imap->select($to_folder);
    my $status = $imap->status($to_folder);
    print Dumper $status if ($debug ==3);

    #fetch the messages already present in the archive.
    #and store their ids in a hash
    my $to_folder_msgs = $imap->search('ALL');
    my $msgcount = (defined $to_folder_msgs) ? @$to_folder_msgs : 0;
    print "Found $msgcount messages in $to_folder on archive server\n" if ($debug >= 2);
    my $teller = 0;
    foreach my $message (@$to_folder_msgs) {
        my $summaries = $imap->get_summaries($message);
        if (scalar @$summaries > 1) {
            die "multiple records returned, unexpected\n";
        }
        my $message_id = $summaries->[0]->message_id;
        $message_id =~ s/^\s+//;
        $message_id =~ s/\s+$//;
        print "MessageID $message_id found in $to_folder on imap server\n" if ($debug >=2);
        $to_message_ids{$message} = $message_id;
        $teller++;
        if ($teller > 500) {
            my $res = $from_imap->noop; #keep the connection alive;
            print "from_imap kept alive\n" if ($debug ==3);
            $teller = 0;
        }
    }
}

##################################################################
##                       filter_already_there                   ##
##                                                              ##
## function that filters out the already present messages from  ##
## the messagelist in the from_imap_folder. so that those       ##
## messages will not be copied again to the archive folder.     ##
##################################################################

sub filter_already_there {
    foreach my $msgid (values %to_message_ids) {
        print "expecting to delete msgid $msgid\n" if ($debug >=2);
        if (exists $from_message_ids{$msgid}) {
            my $val = delete $from_message_ids{$msgid};
            print "message $msgid already located on imap, was from-imap messageid $val\n" if ($debug >=2);
        }
    }
}

##################################################################
##                       copy_remaining                         ##
##                                                              ##
## function that will do the copying the messages that do need  ##
## Rto be copied to the archive folder on the imap server. It   ##
## will also try to establish the date the message was received ##
## effectively, to set that date effectively in the imap store. ##
##################################################################

sub copy_remaining {
    my $from_imap = shift;
    my $to_imap   = shift;
    my $from_folder = shift;
    my $to_folder = shift;

    #take care that we are using the right folders...
    my $fres = $from_imap->select($from_folder);
    my $from_status = $from_imap->status($from_folder);
    my $to_res = $to_imap->select($to_folder);
    my $to_status = $to_imap->status($to_folder);
    my $teller=0;

    foreach my $message (sort { $a <=> $b } values %from_message_ids) {
        print "Going to copy from imap folder $from_folder message nbr $message\n" if ($debug>=2);
        my $summary = $from_imap->get_summaries($message);
        my $fmtdate = $summary->[0]->{internaldate};
        my $mess    = $from_imap->get_rfc822_body($message);
        my $flags   = $from_imap->get_flags($message);
        
        $to_imap->append($to_folder, $mess, $flags, $fmtdate);
        $teller++;
    }
    print "Done copying folder $from_folder: $teller messages copied to archive\n" if ($debug);
}

