#!/usr/bin/perl 

use strict;
use warnings;

use Config::File qw(read_config_file);
use Data::Dumper;
use DateTime::Format::DateParse;
use IO::Socket::SSL;
use Mail::Mbox::MessageParser;
use Mail::POP3Client;
use Net::IMAP::Client;

my $config_file = shift;
my $config = read_config_file($config_file) || die "could not read configfile $config_file\n";

my $debug = $config->{debug};

#setting up connecting to the servers etc...
print "going to connect to popserver (fromhost)\n" if ($debug ==3);
my $from_socket = IO::Socket::SSL->new(
    PeerAddr    => $config->{fromhost},
    PeerPort    => 995,
#    SSL_ca_file => $config->{from_SSL_ca_file},
    Proto       => 'tcp'
) || die "connecting from_host: error=$!, ssl_error=$SSL_ERROR";
print "connected to popserver (fromhost)\n" if ($debug >=2);

print "going to connect to imap server (tohost)\n" if ($debug ==3);
my $to_socket = IO::Socket::SSL->new(
    PeerAddr    => $config->{tohost},
    PeerPort    => 993,
    SSL_ca_file => $config->{to_SSL_ca_file},
    Proto       => 'tcp'
) || die "connecting to_host: error=$!, ssl_error=$SSL_ERROR";
print "connected to imap server (tohost)\n" if ($debug >=2);


print "initialising popmailclient\n" if ($debug ==3);
my $pop = new Mail::POP3Client(
    DEBUG   => 1,
    TIMEOUT => 2,
);
print "setting usernames and password and connection\n" if ($debug ==3);
$pop->User($config->{fromusername});
$pop->Pass($config->{frompassword});
$pop->Socket($from_socket);

print "authenticating at popserver\n" if ($debug ==3);
my $from_res = $pop->Connect();
if (!$from_res) {
    die $pop->Message();
} else {
    print "Successfully authenticated and connected to popserver\n" if ($debug);
}

my $imap = Net::IMAP::Client->new(
    DEBUG   => 1,
    TIMEOUT => 2,
    socket  => $to_socket,
);

print "Going to authenticate at imap server (to-server)\n" if ($debug ==3);
my $to_res = $imap->login($config->{tousername},$config->{topassword});
if (!$to_res) {
    die $imap->last_error();
} else {
    print "Succesfully authenticated and connected to imap server (to_server)\n" if ($debug >=2);
}
#done setting up...

#global vars
my %from_message_ids;
my %to_message_ids;

read_pop_box($pop);                               #fill the $from_message_ids;
print Dumper \%from_message_ids if ($debug ==3);
my $to_folder = $config->{prefix}.".INBOX";
read_imap_folder($imap, $to_folder);              #fill the messages already there.

## filter out the messages that are already in the archive.
filter_already_there();

#the remaining messages need to be copied
copy_remaining($pop, $imap);

print "Done storing the popmailbox\n" if ($debug);

if (!$config->{fetch_maildir_archive}) {
    print "fetching maildir data not configured, so done\n";
    exit;
}

#clean up the temp directory
system("rm -rf ./tmp/");
#Continue fetching the mail directory.
my $cmd = "sshpass -p '$config->{frompassword}' scp -r $config->{fromusername}\@mail.bertrick.nl:~/Mail/ ./tmp/";
system($cmd);

opendir(my $dh, "./tmp") or die "Cannot open ./tmp dir: $!\n";
my @files = grep {$_ !~ /^\./} readdir($dh);
close $dh;

foreach my $file (@files) {
    %from_message_ids = ();
    %to_message_ids = ();
    $to_folder = $config->{prefix}.".SEND.$file";
    print "Handling mbox $file\n" if ($debug);
    my $mb = new Mail::Mbox::MessageParser(
        {
            'file_name'    => "tmp/$file",
            'enable_cache' => 0,
            'enable_grep'  => 0,
        }
    );
    my $full_messages = read_mbox($mb);
    print Dumper \%from_message_ids if ($debug ==3);

    read_imap_folder($imap, $to_folder);     #fill the messages already there.
    filter_already_there();                  #filter out the messages already archived
    copy_mbox_remaining($imap, $file, $to_folder, $full_messages);
}




##################################################################
##                       simplify header                        ##
##                                                              ##
## helper function to combine multiline header lines to one     ##
## line.                                                        ##
##################################################################

sub simplify_header {
    my @header = @_;

#    print Dumper \@header;

    my @return;
    foreach (my $i = 0; $i < @header; $i++) {
        my $line;
        $line = $header[$i];
        my $check = 1;
        my $j = 1;
        while ($check and ($i+$j < @header)) {
            if ($header[$i+$j] =~ /^\s+/) {
                my $attach = $header[$i+$j];
                $attach =~ s/^\s+//;
                $line .= " ".$attach;
            } else {
                $i = $i+$j-1;
                $check = 0;
            }
            $j++;
        }
        push @return, $line;
    }
    return @return;
}

##################################################################
##                       read_pop_box                           ##
##                                                              ##
## function that fills the list of potential messages that may  ##
## need to be transfered to the archive mailfolder on the imap  ##
## server.                                                      ##
##################################################################

sub read_pop_box {
    my $pop = shift;

    print "aantal messages found in mailbox: ".$pop->Count()."\n" if ($debug);
    for(my $i = 1; $i <= $pop->Count(); $i++ ) {
        my $found =0;
        my @header = $pop->Head( $i );
        my @sheader = simplify_header(@header);
        for(my $j = 0; $j < @sheader; $j++) {
            if ($sheader[$j] =~ /^Message-ID:\s*/i) {
                #found messageID.
                print "found messageID $sheader[$j]\n" if ($debug >=2);
                my $messageid = $sheader[$j];
                $messageid =~ s/^Message-ID:\s*//i;
                $messageid =~ s/\s*$//;
                if (exists $from_message_ids{$messageid}) {
                    print "Messageid $messageid not unique in popbox ($i and "
                        . $from_message_ids{$messageid} . ")\n" if ($debug);
                }
                $from_message_ids{$messageid} = $i;
                $found = 1;
            }
        }
        if (!$found) {
            print "No MessageID found for message $i\n";
        } else {
            print "MessageID seen for message $i\n" if ($debug ==3);
        }
    }
}

##################################################################
##                       read_imap_folder                       ##
##                                                              ##
## function that fills the list of already present messages in  ##
## the archive folder. Those messages do not need to be         ##
## transfered to the imap server.                               ##
##################################################################

sub read_imap_folder {
    my $imap = shift;
    my $to_folder = shift;

    my $capabil = $imap->capability();
    if ($debug ==3) {
        print "Imap capabilities:\n";
        print Dumper $capabil;
    }
    my @folders = $imap->folders();
    if ($debug ==3) {
        print "Found folders at imap server:\n";
        print Dumper \@folders;
    }

    my @folderexists = grep { $_ eq $to_folder } @folders;
    if (!@folderexists) {
        $imap->create_folder($to_folder);
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
    print "Found ". scalar @$to_folder_msgs. " messages in $to_folder on imap server\n" if ($debug >= 2);
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
    }
}

##################################################################
##                       filter_already_there                   ##
##                                                              ##
## function that filters out the already present messages from  ##
## the messagelist in the popbox. so that those messages will   ##
## not be copied again to the archive folder.                   ##
##################################################################

sub filter_already_there {
    foreach my $msgid (values %to_message_ids) {
        print "expecting to delete msgid $msgid\n" if ($debug >=2);
        if (exists $from_message_ids{$msgid}) {
            my $val = delete $from_message_ids{$msgid};
            print "message $msgid already located on imap, was pop messageid $val\n" if ($debug >=2);
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
    my $pop = shift;
    my $imap = shift;

    foreach my $message (sort { $a <=> $b } values %from_message_ids) {
        print "Going to copy popbox message nbr $message\n" if ($debug);
        my $mess    = $pop->Retrieve($message);
        my @header  = $pop->Head($message);
        my @sheader = simplify_header(@header);
        my $received;
        my $fmtdate=undef;
        foreach my $line (@sheader) {
            if ($line =~ /^Received:\s*/) {
                $received = $line;
                $received =~ s/^Received:\s*//;
                last;
            }
        }
        if ($received) {
            $received =~ /;\s*(.*)/;
            my $date = $1;
            my $dt = DateTime::Format::DateParse->parse_datetime( $date );
            $fmtdate = $dt->strftime("%d-%b-%Y %T %z");
            print "setting imap internal date to: $fmtdate\n" if ($debug >=2);
        }
        
        $imap->append($to_folder, \$mess, ['\\SEEN'], $fmtdate);
    }
}

##################################################################
##                       read_mbox                              ##
##                                                              ##
## function that will read all the messages from a              ##
## Mail::Mbox::MessageParser object and puts the messages in    ##
## a array, and analyses the headers for messages id's and      ##
## stores those in the global var for that purpose              ##
##################################################################

sub read_mbox {
    my $mb = shift;

    my @full_messages;
    my $i=0;
    while(!$mb->end_of_file())
    {
        $i++;
        my $found =0;

        my $email = $mb->read_next_email();
        print "Email $i ingelezen\n" if ($debug >=2);
        my $msg = $$email;
        push @full_messages, $msg;
        my ($head, @rest) = split /\n\n/, $msg;
        my @header = split /\n/, $head;
        my @sheader = simplify_header(@header);
        for(my $j = 0; $j < @sheader; $j++) {
            if ($sheader[$j] =~ /^Message-ID:\s*/i) {
                #found messageID.
                print "found messageID $sheader[$j]\n" if ($debug >=2);
                my $messageid = $sheader[$j];
                $messageid =~ s/^Message-ID:\s*//i;
                $messageid =~ s/\s*$//;
                $from_message_ids{$messageid} = $i;
                $found = 1;
                last;
            }
        }
        if (!$found) {
            print "No MessageID found for message $i\n";
        } else {
            print "MessageID seen for message $i\n" if ($debug ==3);
        }
    }
    return \@full_messages;
}

##################################################################
##                    copy_mbox_remaining                       ##
##                                                              ##
## function that will do the copying the messages that do need  ##
## to be copied to the archive folder on the imap server (from  ##
## a mbox folder format).It will also try to establish the date ##
## the message was send effectively, to set that date           ##
## effectively in the imap store.                               ##
##################################################################

sub copy_mbox_remaining {
    my $imap = shift;
    my $file = shift;
    my $to_folder = shift;
    my $full_messages = shift;

    foreach my $message (sort { $a <=> $b } values %from_message_ids) {
        print "Going to copy from mbox $file message nbr $message\n" if ($debug);
        my $mess    = $full_messages->[$message-1];
        my ($head, @rest) = split /\n\n/, $mess;
        my @header = split /\n/, $head;
        my @sheader = simplify_header(@header);
        my $msgdate;
        my $fmtdate=undef;
        foreach my $line (@sheader) {
            if ($line =~ /^Date:\s*/) {
                $msgdate = $line;
                $msgdate =~ s/^Date:\s*//;
                last;
            }
        }
        if ($msgdate) {
            my $dt = DateTime::Format::DateParse->parse_datetime( $msgdate );
            $fmtdate = $dt->strftime("%d-%b-%Y %T %z");
            print "setting imap internal date to: $fmtdate\n" if ($debug >=2);
        }
        
        $imap->append($to_folder, \$mess, ['\\SEEN'], $fmtdate);
    }
}
