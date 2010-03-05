package Mjollnir::Monitor;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.01;

use POE;
use POE::Session;
use POE::Kernel;
use Net::Pcap ();
use Socket ();
use NetPacket::Ethernet qw(:types);
use NetPacket::IP qw(:protos);
use NetPacket::UDP;

sub get_devices {
    my %devinfo;
    my $err;
    my @devs = Net::Pcap::findalldevs(\%devinfo, \$err);
    return %devinfo;
}

sub spawn {
    my $class = shift;
    my $device = shift;
    return POE::Session->create(
        inline_states => {
            _start => \&_start,
            shutdown => \&shutdown,
            poll => \&poll,
            got_packet => \&got_packet,
            set_listener => \&set_listener,
        },
        heap => {
            device => $device,
        },
    );
}

sub _start {
    my ($kernel, $heap, $listener) = @_[KERNEL, HEAP, ARG0];
    $heap->{target_session} = $_[SENDER];

    my $err;
    my $device = $heap->{device};
    
    my $network_raw;
    my $mask_raw;
    Net::Pcap::lookupnet($device, \$network_raw, \$mask_raw, \$err);
    $heap->{network_raw} = $network_raw;
    $heap->{mask_raw} = $mask_raw;
    my $network = $heap->{network} = join('.', unpack('C4', Socket::inet_aton($network_raw)));
    my $mask = $heap->{mask} = 32 - log(2**32 - $mask_raw) / log 2;

    my $pcap = $heap->{pcap} = Net::Pcap::open_live($device, 10, 0, 0, \$err);

    my $filter;
    Net::Pcap::compile($pcap, \$filter, "udp and dst port 28960 and dst net $network/mask", 0, $mask_raw);
    Net::Pcap::setfilter($pcap, $filter);

    $heap->{timer} = $kernel->delay_set( 'poll', 0.5 );
}

sub poll {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    Net::Pcap::dispatch($heap->{pcap}, -1, sub {
        my (undef, $header, $packet) = @_;
        $kernel->yield( got_packet => $packet );
    }, 1);
    $heap->{timer} = $kernel->delay_set( 'poll', 0.5 );
}

sub shutdown {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
}

sub got_packet {
    my ($kernel, $heap, $pkt) = @_[KERNEL, HEAP, ARG0];
    my $ether = NetPacket::Ethernet->decode($pkt);
    return
        unless $ether->{type} && $ether->{type} == ETH_TYPE_IP;
    my $ip = NetPacket::IP->decode($ether->{data});
    return
        unless $ip->{proto} && $ip->{proto} == IP_PROTO_UDP;
    my $udp = NetPacket::UDP->decode($ip->{data});
    my $data = $udp->{data};
    return unless $data;
    if ($data =~ m{^\xff{4}connect [0-9a-f]+ "\\([^"]+)"}) {
        my $playerdata = $1;
        my %data = split /\\/, $playerdata;
        $kernel->post( $heap->{target_session}, 'player_connect', {
            ip       => $ip->{src_ip},
            name     => $data{name},
            steam_id => $data{steamid},
        } );
    }
    elsif ($data =~ /^\xff{4}\dmemberJoin [^ ]* ([0-9a-f]{8})([0-9a-f]{8}) \w+\x00.{44}([^\x00]+)/) {
        my $steam_id = $2 . $1;
        my $player_name = $3;
        $kernel->post( $heap->{target_session}, 'player_join', {
            ip       => $ip->{src_ip},
            name     => $player_name,
            steam_id => $steam_id,
        } );
    }
    elsif ($data =~ /^\xff{4}\dident\x00([^\x00]+)/) {
        my $player_name = $1;
        $kernel->post( $heap->{target_session}, 'player_ident', {
            ip       => $ip->{src_ip},
            name     => $player_name,
        } );
    }
#    elsif ($data =~ /partystate/) {
#    }
}

1;

__END__

=head1 NAME

Mjollnir::Web - Web interface for Mjollnir

=head1 AUTHOR

Graham Knop <haarg@haarg.org>

=head1 LICENSE

Copyright (c) 2010, Graham Knop
 
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0. For more details, see the
full text of the licenses in the directory LICENSES.

=cut