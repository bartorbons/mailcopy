#!/usr/bin/perl 
use strict;
use warnings;

package ImapCopy;
use Data::Dumper;

my $allowed_keys = {
    from             => {required => 1},
    to               => {required => 1},
    prefix           => {required => 1},
    folder_separator => {required => 1},
    debug            => {required => 1},
    diff             => {required => 0},
    from_message_ids => {required => 0},
    to_message_ids   => {required => 0}
};


##################################################################
##                           new                                ##
##                                                              ##
## constructor of the class object.                             ##
## checks whether the required arguments are provided           ##
##################################################################

sub new {
    my $class = shift;
    #required keys: from, to, prefix, folder_separator, debug
    my (%args) = @_;
    my %set;

    foreach my $k (keys %args) {
        if (!exists $allowed_keys->{$k}) {
            die "unexpected attribute '$k' for class creation\n";
        }
        $set{$k}=$args{$k};
    }
    foreach my $k (grep { $allowed_keys->{$_}->{required} eq 1 } keys %$allowed_keys) {
        if (!exists $set{$k}) {
            die "required attribute '$k' missing for class creation\n";
        }
    }

    return bless {%set}, $class;
}

##################################################################
##                           get                                ##
##                                                              ##
## getter method to retrieve the class attributes from the      ##
## object.                                                      ##
##################################################################

sub get {
    my $self = shift;
    my ($key)  = @_;
    die "unknown key '$key' for class\n" if (!exists $allowed_keys->{$key});

    return $self->{$key};
}

##################################################################
##                           set                                ##
##                                                              ##
## setter method to set the class attributes to the object.     ##
##################################################################

sub set {
    my $self = shift;
    my ($key, $val) = @_;
    die "unknown key '$key' for class\n" if (!exists $allowed_keys->{$key});

    return $self->{$key} = $val;
}

##################################################################
##                           log                                ##
##                                                              ##
## method to filter whether the output is wished for to be      ##
## actualy printed to output.                                   ##
##################################################################

sub log {
    my $self = shift;
    my $level = shift;

    printf @_ if ($level <= $self->get("debug"));
}

##################################################################
##                              run                             ##
##                                                              ##
## method that does the work.                                   ##
## queries to the from-imap server all the folders and then     ##
## loops for all the folders to get all the messages from the   ##
## from imap, stores their ids, does the same for all the       ##
## messages in the to imap server, and makes the diff, and then ##
## copies the diffs to the to correct folder in the to imap     ##
## server                                                       ##
##################################################################

sub run {
  my $self = shift;
  my $from = $self->get("from");
  my $to   = $self->get("to");

  #and get to work:
  my @folders = $from->folders();
  my $fseperator = $self->get("folder_separator");
  my $fcounter;

  foreach my $folder (@folders) {
    #clean up previous folder data....
    $self->set("from_message_ids", \());
    $self->set("to_message_ids", \());
    $self->set("diff", \());

    my $folder_repl = $folder;
    $folder_repl =~ s/$fseperator/\./g;
    my $to_folder = $self->get("prefix").".$folder_repl";
    $self->log(1, "Handling folder $folder\n");
    $self->read_from_imap_folder($from, $folder, $to);      #fill the from message_ids.
    $self->read_to_imap_folder($to, $to_folder, $from);     #fill the message_ids already there.
    $self->filter_already_there();                          #filter out the messages already archived
    $self->copy_remaining($from, $to, $folder, $to_folder); #copy what needs to be copied.
    $fcounter++;
}
$self->log(1, "handled $fcounter folders to Mailarchief\n");
}

##################################################################
##                    read_from_imap_folder                     ##
##                                                              ##
## method that fills the list of potential messages that may    ##
## need to be transfered to the archive mailfolder on the imap  ##
## server. (The to_imap needs to be passed in so that the       ##
## connection to the to_imap server can be kept alive for big   ##
## from-imap folders)                                           ##
##################################################################

sub read_from_imap_folder {
    my $self = shift;
    my $imap = shift;
    my $folder = shift;
    my $to_imap = shift;

    my %from_message_ids;

    my $select = $imap->select($folder);
    my $status = $imap->status($folder);
    $self->log(3, Dumper $status);
    my $from_folder_msgs = $imap->search('ALL');
    my $msgcount = (defined $from_folder_msgs) ? @$from_folder_msgs : 0;
    $self->log(2, "Found $msgcount messages in $folder on from imap server\n");
    my $teller = 0;
    foreach my $message (@$from_folder_msgs) {
        my $summaries = $imap->get_summaries($message);
        if (scalar @$summaries > 1) {
            die "multiple records returned, unexpected\n";
        }
        my $message_id = $summaries->[0]->message_id;
        $message_id =~ s/^\s+// if (defined $message_id && length($message_id) >0);
        $message_id =~ s/\s+$// if (defined $message_id && length($message_id) >0);
        if (!defined $message_id || length($message_id) ==0) {
            die "from imapserver folder $folder, message $message has no id\n";
        }
        $self->log(2,"MessageID $message_id found in $folder on from imap server\n");
        $from_message_ids{$message_id} = $message;
        $teller++;
        if ($teller > 500) {
            my $res = $to_imap->noop; #keep the connection alive;
            $self->log(3,"to_imap kept alive\n");
            $teller = 0;
        }
    }
    $self->log(3, Dumper \%from_message_ids);
    $self->set("from_message_ids", \%from_message_ids);
}

##################################################################
##                     read_to_imap_folder                      ##
##                                                              ##
## method that fills the list of already present messages in    ##
## the archive folder. Those messages do not need to be         ##
## transfered to the imap server. (The from_imap needs to be    ##
## passed in to keep the connection alive for big to_imap       ##
## folders)                                                     ##
##################################################################

sub read_to_imap_folder {
    my $self = shift;
    my $imap = shift;
    my $to_folder = shift;
    my $from_imap = shift;

    my %to_message_ids;

    my @to_folders = $imap->folders();

    my @folderexists = grep { $_ eq $to_folder } @to_folders;
    if (!@folderexists) {
        my $res = $imap->create_folder($to_folder) or die "Could not create imap folder $to_folder\n";
        $self->log(1,"Folder $to_folder created on mail archive\n");
    } else {
        $self->log(1, "Using existing folder $to_folder\n");
    }

    my $fres = $imap->select($to_folder);
    my $status = $imap->status($to_folder);
    $self->log(3, Dumper $status);

    #fetch the messages already present in the archive.
    #and store their ids in a hash
    my $to_folder_msgs = $imap->search('ALL');
    my $msgcount = (defined $to_folder_msgs) ? @$to_folder_msgs : 0;
    $self->log(2,"Found $msgcount messages in $to_folder on archive server\n");
    my $teller = 0;
    foreach my $message (@$to_folder_msgs) {
        my $summaries = $imap->get_summaries($message);
        if (scalar @$summaries > 1) {
            die "multiple records returned, unexpected\n";
        }
        my $message_id = $summaries->[0]->message_id;
        $message_id =~ s/^\s+// if (defined $message_id && length($message_id) >0);
        $message_id =~ s/\s+$// if (defined $message_id && length($message_id) >0);
        $self->log(2,"MessageID $message_id found in $to_folder on imap server\n");
        $to_message_ids{$message} = $message_id;
        $teller++;
        if ($teller > 500) {
            my $res = $from_imap->noop; #keep the connection alive;
            $self->log(3,"from_imap kept alive\n");
            $teller = 0;
        }
    }
    $self->set("to_message_ids", \%to_message_ids);
}

##################################################################
##                       filter_already_there                   ##
##                                                              ##
## method that filters out the already present messages from    ##
## the messagelist in the from_imap_folder. so that those       ##
## messages will not be copied again to the archive folder.     ##
##################################################################

sub filter_already_there {
    my $self = shift;

    my $to_message_ids = $self->get("to_message_ids");
    my $from_message_ids = $self->get("from_message_ids");
    foreach my $msgid (values %$to_message_ids) {
        $self->log(2,"expecting to delete msgid $msgid\n");
        if (exists $from_message_ids->{$msgid}) {
            my $val = delete $from_message_ids->{$msgid};
            $self->log(2,"message $msgid already located on imap, was from-imap messageid $val\n");
        }
    }
    $self->set("diff", $from_message_ids);
}

##################################################################
##                       copy_remaining                         ##
##                                                              ##
## Method that will do the copying the messages that do need    ##
## Rto be copied to the archive folder on the imap server. It   ##
## will also try to establish the date the message was received ##
## effectively, to set that date effectively in the imap store. ##
##################################################################

sub copy_remaining {
    my $self = shift;
    my $from_imap = shift;
    my $to_imap   = shift;
    my $from_folder = shift;
    my $to_folder = shift;

    #take care that we are using the right folders...
    my $fres = $from_imap->select($from_folder);
    my $from_status = $from_imap->status($from_folder);
    my $to_res = $to_imap->select($to_folder);
    my $to_status = $to_imap->status($to_folder);
    my $diff = $self->get("diff");
    my $teller=0;

    foreach my $message (sort { $a <=> $b } values %$diff) {
        $self->log(2,"Going to copy from imap folder $from_folder message nbr $message\n");
        my $summary = $from_imap->get_summaries($message);
        my $fmtdate = $summary->[0]->{internaldate};
        my $mess    = $from_imap->get_rfc822_body($message);
        my $flags   = $from_imap->get_flags($message);
        
        $to_imap->append($to_folder, $mess, $flags, $fmtdate);
        $teller++;
    }
    $self->log(1,"Done copying folder $from_folder: $teller messages copied to archive\n");
}

1;
