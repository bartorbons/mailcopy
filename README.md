Mail archive copier.

This repo contains two scripts to copy mail from a mailserver
to a mailarchive. One script for when the mailserver is a
pop3(s) server, and one variant for when the mailserver is
a imap server.

The desination must be a imap server. It can be a server running
in private ip-space, or running on an official reachable place
on an official site.

I run the archiving server in my home network, so I cannot get
an official certificate, so I generated a selfsigned certificate
so that is why the certificate parameters are there.

The main purpose is that the archiving server is there just for that,
for archiving all your mail. So it assumes it can fetch mail for
multiple sources, and keep those mailboxes intact, but archived
to the archive. So each mailbox you want to archive, can be prefixed
with a unique prefix, to keep the mailboxes apart.

If you are reading mail through some pop mailserver, and have the
mailagent store (outgoing)mail in your mail directory in mbox format 
on the server, then you can optionally let the pop script copy the mail
directory to the tmp directory where you are running the script, and then 
the files in the tmp directory are read as mbox files, and also 
synced with your archive. (synced with the imap folder 
<prefix>.SEND.<file>)

Prerequisites:
You have set up somewhere some mailarchive where you want to
store your mail. I have set up a dovecot server on some virtual
machine, but your choise, your option.
You should be running this software for some kind of unix-type
machine. Where you have perl running, with the folliwing perl
modules installed. Whether you have them installed through some
packagemananger for your system, or through some cpan variants
does not matter.
Config::File
Data::Dumper
IO::Socket::SSL
Net::IMAP::Client
DateTime::Format::DateParse
Mail::Mbox::MessageParser
Mail::POP3Client

to run the tests, the following perl modules are needed:
Test::MockObject
Test::More
Test::Exception




INSTALLING
Install the files in this repo in some subdir under your homedir
on your system. Create a config file in the etc directory for each
mailserver you are archiving.

