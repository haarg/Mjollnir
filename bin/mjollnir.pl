#!perl
use strict;
use warnings;
use Getopt::Long qw(:config no_auto_abbrev);
use Mjollnir;
use Mjollnir::Monitor;

Getopt::Long::GetOptions(
    'd|dev=s' => \(my $device),
);

if (!$device) {
    my %devinfo = Mjollnir::Monitor->get_devices;
    warn scalar keys %devinfo;
    if (keys %devinfo == 1) {
        ($device) = values %devinfo;
    }
    else {
        warn "Multiple network devices detected.  Please specify one with --dev\n";
        for my $dev (sort keys %devinfo) {
            warn "$dev : $devinfo{$dev}\n";
        }
        exit;
    }
}
print "Monitoring device $device\n";

Mjollnir->run($device);
