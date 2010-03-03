#!perl
use strict;
use warnings;
use Net::Pcap ();
use Net::Pcap::Easy;
use Getopt::Long qw(:config no_auto_abbrev);
use File::Spec;
use IO::File;
use Cwd ();

Getopt::Long::GetOptions(
    'd|dev=s' => \(my $device),
    'l|log=s' => \(my $log_file),
);

if (!$device) {
    my %devinfo;
    my $err;
    my @devs = Net::Pcap::pcap_findalldevs(\%devinfo, \$err);
    if (@devs == 1) {
        $device = $devs[0];
    }
    else {
        warn "Multiple network devices detected.  Please specify one with --dev\n";
        for my $dev (@devs) {
            warn "$dev : $devinfo{$dev}\n";
        }
        exit;
    }
}
print "Monitoring device $device\n";

if (!$log_file) {
    $log_file = File::Spec->catpath((File::Spec->splitpath(Cwd::realpath(__FILE__)))[0,1] , 'mw2players.log');
    print "Logging to $log_file\n";
}

open my $log_fh, '>>', $log_file;
$log_fh->autoflush(1);

my $npe = Net::Pcap::Easy->new(
    dev              => $device,
    filter           => 'udp and dst port 28960',
    packets_per_loop => 10,

    udp_callback => sub {
        my ($npe, $ether, $ip, $udp) = @_;
        my $data = $udp->{data};
        if ($data =~ m{\bconnect [0-9a-f]+ "\\([^"]+)"}) {
            my $playerdata = $1;
            my %data = split /\\/, $playerdata;
            print {$log_fh} "$ip->{src_ip}\t$data{name}\n";
        }
    },
);

1 while $npe->loop;
