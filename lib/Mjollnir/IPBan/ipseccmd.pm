package Mjollnir::IPBan::ipseccmd;
use strict;
use warnings;

our $VERSION = 0.01;

use Exporter qw(import);

our @EXPORT = qw(ban_ip clear_bans);

sub ban_ip {
    my $ip = shift;
    my $output = `ipseccmd -n BLOCK -f $ip+0:28960:UDP 2>&1`;
    if ($output =~ /error/) {
        return;
    }
    return 1;
}

sub clear_bans {
    my $output = `ipseccmd -u 2>&1`;
    if ($output =~ /error/) {
        return;
    }
    return 1;
}

1;

__END__

=head1 NAME

Mjollnir::IPBans::ipseccmd - IP banning controls using ipseccmd.exe

=head1 AUTHOR

Graham Knop <haarg@haarg.org>

=head1 LICENSE

Copyright (c) 2010, Graham Knop
 
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0. For more details, see the
full text of the licenses in the directory LICENSES.

=cut
