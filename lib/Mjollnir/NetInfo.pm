package Mjollnir::NetInfo;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.01;

my $ip_re = qr{[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+};

sub get_default_device {
    my $class = shift;
    my $local_ip;
    my @routes = `route print`;
    for my $route ( @routes ) {
        my ($network, $netmask, $gateway, $interface, $metric)
            = $route =~ /\A\s*($ip_re)\s+($ip_re)\s+($ip_re)\s+($ip_re)\s+([0-9]+)/;
        next
            if !$network;
        if ($network eq '0.0.0.0' && $netmask eq '0.0.0.0') {
            $local_ip = $interface;
        }
    }

    if (! $local_ip) {
        $local_ip = $class->get_local_ip;
    }
    my $device
        = $class->get_device_for_ip_pcap($local_ip)
        || $class->get_device_for_ip_wql($local_ip);
    return $device;
}

sub get_local_ip {
    my $class = shift;
    require Net::Route::Table;
    require Net::Netmask;
    require Socket;

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

sub get_device_for_ip_pcap {
    my $class = shift;
    my $ip = shift;

    require Net::Pcap;
    require Net::Netmask;

    my $err;
    my @devs = Net::Pcap::findalldevs( {}, \$err );
    for my $dev (@devs) {
        my $network;
        my $mask;
        Net::Pcap::lookupnet($dev, \$network, \$mask, \$err);
        next
            if (! $network || ! $mask);
        $network = join( '.', unpack( 'C4', Socket::inet_aton($network) ) );
        $mask = 32 - log( 2**32 - $mask ) / log 2;
        my $netmask = Net::Netmask->new("$network/$mask");
        if ($netmask->match($ip)) {
            return $dev;
        }
    }
}

sub get_device_for_ip_wql {
    my $class = shift;
    my $ip = shift;

    require DBI;
    require DBD::WMI;

    my $dbh = DBI->connect('dbi:WMI:');
    my $sth = $dbh->prepare(<<'END_WQL');
      SELECT * from Win32_NetworkAdapterConfiguration
      WHERE IPEnabled = True
END_WQL
    $sth->execute;

    my $device;
    while (my ($net) = $sth->fetchrow) {
        if ( grep { $_ eq $ip } @{ $net->{IPAddress} } ) {
            $device = '\Device\NPF_' . $net->{SettingID};
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
