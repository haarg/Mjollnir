package Mjollnir::Monitor;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.02;

use POE;
use POE::Session;
use POE::Kernel;
use Net::Pcap ();
use Socket    ();
use NetPacket::Ethernet qw(:types);
use NetPacket::IP qw(:protos);
use NetPacket::UDP;

sub get_devices {
    my %devinfo;
    my $err;
    my @devs = Net::Pcap::findalldevs( \%devinfo, \$err );
    return %devinfo;
}

sub detect_default_device {
    eval { require Mjollnir::NetInfo }
        or die "Unable to detect network info.\n";
    my $ip = Mjollnir::NetInfo::get_local_ip();
    my $device = Mjollnir::NetInfo::get_device_for_ip($ip);
    return $device;
}

sub spawn {
    my $class  = shift;
    my $device = shift // detect_default_device();
    return POE::Session->create(
        heap => { device => $device },
        package_states => [
            $class => [qw(
                _start
                shutdown
                poll
                got_packet
            )],
        ],
    );
}

sub _start {
    my ( $kernel, $heap, $listener ) = @_[ KERNEL, HEAP, ARG0 ];
    $heap->{target_session} = $_[SENDER]->ID;

    my $err;
    my $device = $heap->{device};

    my $network_raw;
    my $mask_raw;
    Net::Pcap::lookupnet( $device, \$network_raw, \$mask_raw, \$err );
    $heap->{network_raw} = $network_raw;
    $heap->{mask_raw}    = $mask_raw;
    my $network = $heap->{network}
        = join( '.', unpack( 'C4', Socket::inet_aton($network_raw) ) );
    my $mask = $heap->{mask} = 32 - log( 2**32 - $mask_raw ) / log 2;

    my $pcap = $heap->{pcap}
        = Net::Pcap::open_live( $device, 10, 0, 0, \$err );

    $heap->{timer} = $kernel->delay_set( 'poll', 0.5 );
    print "Monitoring network device:\n\t$device\n";
}

sub shutdown {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $kernel->alarm_remove(delete $heap->{timer});
    Net::Pcap::close(delete $heap->{pcap});
    delete $heap->{target_session};
    print "Stopping network monitor.\n";
    return 1;
}

sub poll {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    Net::Pcap::dispatch(
        $heap->{pcap},
        -1,
        sub {
            my ( undef, $header, $packet ) = @_;
            $kernel->yield( got_packet => $packet );
        },
        1
    );
    $heap->{timer} = $kernel->delay_set( 'poll', 0.5 );
}

sub got_packet {
    my ( $kernel, $heap, $pkt ) = @_[ KERNEL, HEAP, ARG0 ];
    my $ether = NetPacket::Ethernet->decode($pkt);
    return
        unless $ether->{type} && $ether->{type} == ETH_TYPE_IP;
    my $ip = NetPacket::IP->decode( $ether->{data} );
    return
        unless $ip->{proto} && $ip->{proto} == IP_PROTO_UDP;
    my $udp  = NetPacket::UDP->decode( $ip->{data} );
    return
        unless $udp->{dest_port} == 28960;
    my $data = $udp->{data};
    return
        unless $data;
    if (not $data =~ s/\A\xff{4}//msx) {
        return;
    }
    print "$ip->{dest_ip}\n";
    if ( $data =~ m{
        \A
        connect[ ][0-9a-f]+[ ]
        "\\([^"]+)"
    }msx ) {
        my $playerdata = $1;
        my %data = split /\\/, $playerdata;
        my $steam_id = $data{steamid};
        my $high_id = substr($steam_id, -8, 8, '');
        $steam_id = $high_id . ( 0 x (8 - length $steam_id) ) . $steam_id;

        $kernel->post(
            $heap->{target_session},
            'player_connect',
            {
                ip       => $ip->{src_ip},
                name     => $data{name},
                steam_id => $steam_id,
            } );
    }
    elsif ( $data =~ m{
        \A\d
        memberJoin[ ][^ ]*[ ]
        ([0-9a-f]{16})
        [ ]\w+\x00
        .{44}
        ([^\x00]+)
    }msx ) {
        my $steam_id    = $1;
        my $player_name = $2;
        $kernel->post(
            $heap->{target_session},
            'player_join',
            {
                ip       => $ip->{src_ip},
                name     => $player_name,
                steam_id => $steam_id,
            } );
    }
    elsif ( $data =~ m{
        \A\d
        ident\x00
        ([^\x00]+)
    }msx ) {
        my $player_name = $1;
        $kernel->post(
            $heap->{target_session},
            'player_ident',
            {
                ip   => $ip->{src_ip},
                name => $player_name,
            } );
    }
}

sub send_vote {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    print "sending vote\n";
    my $pcap = $heap->{pcap};
    my $data = "\xFF\xFF\xFF\xFF\xFF0veto 1\x00";
#    Net::Pcap::sendpacket($pcap, $packet);
}

1;

__END__

=head1 NAME

Mjollnir::Monitor - Packet monitor for Mjollnir

=head1 AUTHOR

Graham Knop <haarg@haarg.org>

=head1 LICENSE

Copyright (c) 2010, Graham Knop
 
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0. For more details, see the
full text of the licenses in the directory LICENSES.

=cut
