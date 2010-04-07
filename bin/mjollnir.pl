#!perl
use Getopt::Long qw(:config gnu_getopt no_auto_abbrev);

if ($^O eq 'MSWin32') {
    require Win32;
    if (! Win32::IsAdminUser()) {
        Getopt::Long::GetOptions(
            'respawn' => \(my $respawn),
        );
        require Win32::API;

        my @parameters = ($0, @ARGV);
        for my $param (@parameters) {
            if ( $param =~ s/(["\\])/\\$1/g || $param =~ / / ) {
                $param = qq{"$param"};
            }
        }
        my $parameters = join ' ', @parameters;

        my $ShellExecuteEx = Win32::API->new('shell32.dll', 'ShellExecuteEx', ['P'], 'N')
            or die 'Get ShellExecuteEx: ' . Win32::FormatMessage(Win32::GetLastError());

        my $lpVerb       = pack 'A*', 'runas';
        my $lpFile       = pack 'A*', $^X;
        my $lpParameters = pack 'A*', $parameters;

        my $args = pack 'LLLPPPPLLLPLLLL';
        $args = pack 'LLLPPPPLLLPLLLL', length $args, ($respawn ? 0x8000 : 0), 0, $lpVerb, $lpFile, $lpParameters, 0, 1, 0, 0, 0, 0, 0, 0, 0;

        my $ret = $ShellExecuteEx->Call($args)
            or die 'Call ShellExecuteEx: ' . Win32::FormatMessage(Win32::GetLastError());
        exit;
    }
}

require Mjollnir;
my $options = {};
Getopt::Long::GetOptions( $options, qw(
    listen|l=s@
    db_file|db|d=s
    device|dev|D=s
    respawn
)) || die "usage: $0 [ -l<host>:<port> ] [ -D<device> ] [ -d<database> ]\n";
Mjollnir->run($options);
