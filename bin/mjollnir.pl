#!perl
use Mjollnir;
use Getopt::Long qw(:config gnu_getopt no_auto_abbrev);
my $options = {};
Getopt::Long::GetOptions( $options, qw(
    listen|l=s@
    db_file|db|d=s
    device|dev|D=s
)) || die "usage: $0 [ -l<host>:<port> ] [ -D<device> ] [ -d<database> ]\n";
Mjollnir->run($options);

