package Mjollnir::IPBan::netsh;
use strict;
use warnings;

our $VERSION = 0.01;

use Exporter qw(import);

our @EXPORT = qw(ban_ip clear_bans);

sub ban_ip {
    my $ip = shift;

    my $output = `netsh -c "advfirewall firewall" add rule name="Mjollnir Block Out $ip" dir=out action=block remoteip=$ip protocol=udp localport=28960 2>&1`;
    if ($output !~ /Ok/) {
        return;
    }
    $output = `netsh -c "advfirewall firewall" add rule name="Mjollnir Block In $ip" dir=in action=block remoteip=$ip protocol=udp localport=28960 2>&1`;
    if ($output !~ /Ok/) {
        return;
    }
    return 1;
}

sub clear_bans {
    my $output = `netsh -c "advfirewall firewall" delete rule name=all protocol=udp localport=28960 2>&1`;
    if ($output !~ /Ok/) {
        return;
    }
    return 1;
}

1;

__END__

=head1 NAME

Mjollnir::IPBans::netsh - IP banning controls using netsh

=head1 AUTHOR

Graham Knop <haarg@haarg.org>

=head1 LICENSE

Copyright (c) 2010, Graham Knop
 
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0. For more details, see the
full text of the licenses in the directory LICENSES.

=cut
