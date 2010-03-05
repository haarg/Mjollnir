package Mjollnir;
use strict;
use warnings;
use POE;
use POE::Kernel;
use Mjollnir::Monitor;

sub run {
    my $class = shift;
    my $device = shift;
    my $monitor = Mjollnir::Monitor->spawn(device => $device);

    $poe_kernel->run;
}

1;