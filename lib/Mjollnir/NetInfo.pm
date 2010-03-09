package Mjollnir::NetInfo;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.01;

use Socket ();
use Net::Route::Table;
use Net::Netmask;

use DBI;
use DBD::WMI;

sub get_local_ip {
    my $remote_ip = Socket::inet_ntoa(Socket::inet_aton('steampowered.com'));

    my @routes = @{ Net::Route::Table->from_system->all_routes };
    my $local_ip;
    for my $route (@routes) {
        my $mask = Net::Netmask->new($route->destination);
        if ($mask->match($remote_ip)) {
            $local_ip = $route->interface;
            last;
        }
    }

    return $local_ip;
}

sub get_device_for_ip {
    my $ip = shift;
    my $dbh = DBI->connect('dbi:WMI:');
    my $sth = $dbh->prepare(<<'END_WQL');
      SELECT * from Win32_NetworkAdapterConfiguration
      WHERE IPEnabled = True
END_WQL
    $sth->execute;

    my $device;
    while (my ($net) = $sth->fetchrow) {
        if ( grep { $_ eq $ip } @{ $net->{IPAddress} } ) {
            $device = "\\Device\\NPF_$net->{SettingID}";
            last;
        }
    }
    $sth->finish;
    return $device;
}

sub get_ips_for_device {
    my $device = shift;
    $device =~ s/\\Device\\NPF_//;
    my $dbh = DBI->connect('dbi:WMI:');
    my $sth = $dbh->prepare(<<"END_WQL");
      SELECT * from Win32_NetworkAdapterConfiguration
      WHERE SettingID = '$device'
END_WQL
    $sth->execute;

    my @ips;
    while (my ($net) = $sth->fetchrow) {
        push @ips, @{ $net->{IPAddress} };
    }
    $sth->finish;
    return wantarray ? @ips : $ips[0];
}

1;


__END__

=head1 NAME

Mjollnir::NetInfo - Network configuration detection for Mjollnir

=head1 AUTHOR

Graham Knop <haarg@haarg.org>

=head1 LICENSE

Copyright (c) 2010, Graham Knop
 
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0. For more details, see the
full text of the licenses in the directory LICENSES.

=cut
