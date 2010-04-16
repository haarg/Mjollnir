package Mjollnir::Monitor;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.02;

use AnyEvent;
use Net::Pcap ();
use Socket    ();
use NetPacket::Ethernet qw(:types);
use NetPacket::IP qw(:protos);
use NetPacket::UDP;

sub detect_default_device {
    return eval {
        require Mjollnir::NetInfo;
        Mjollnir::NetInfo->get_default_device;
    } || die "Unable to detect network info. $@\n";
}

sub new {
    my $class = shift;
    my $options = (@_ == 1 && ref $_[0]) ? shift : { @_ };
    my $self = bless {}, $class;
    $self->{callback} = $options->{callback} // sub {};
    $self->{device}   = $options->{device} // $self->detect_default_device;
    $self->{logger}   = $options->{logger};
    return $self;
}

sub start {
    my $self = shift;

    $self->{logger}->("Monitoring network device:\n\t$self->{device}\n");

    $self->_init_pcap;

    my $pcap = $self->{pcap};
    $self->{timer} = AnyEvent->timer(
        wait => 0.2,
        interval => 0.2,
        cb   => sub {
            my @pending;
            Net::Pcap::dispatch(
                $pcap, -1,
                sub {
                    my $header = $_[1];
                    my $packet = $_[2];
                    push @{ $_[0] }, ( $header, $packet );
                },
                \@pending
            );
            $self->handle_packets(@pending);
        }
    );
    return $self;
}

sub _init_pcap {
    my $self = shift;

    my $device = $self->{device};
    my $err;

    my $pcap = Net::Pcap::open_live( $device, 1024, 1, 0, \$err );
    $self->{pcap} = $pcap;
    die $err
        if $err;

    my $network;
    my $mask;
    Net::Pcap::lookupnet( $device, \$network, \$mask, \$err );
    die $err
        if $err;
    $self->{network_raw} = $network;
    $self->{mask_raw}    = $mask;
    $self->{network}     = join( '.', unpack( 'C4', Socket::inet_aton($network) ) );
    $self->{mask}        = 32 - log( 2**32 - $mask ) / log 2;

    my $filter_string = "udp and dst port 28960 and dst net $network/$mask";
    my $filter;
    # filters are broken
    #Net::Pcap::compile( $pcap, \$filter, $filter_string, 0, $netmask );
    #Net::Pcap::setfilter( $pcap, $filter );
    $self->{filter} = $filter;
    return 1;
}

sub shutdown {
    my $self = shift;
    delete $self->{timer};
    if ($self->{pcap}) {
        $self->{logger}->("Stopping network monitor.\n");
        Net::Pcap::close(delete $self->{pcap});
    }
    if ($self->{filter}) {
        Net::Pcap::freecode(delete $self->{filter});
    }
    return 1;
}

sub DESTROY {
    my $self = shift;
    $self->shutdown;
}

sub handle_packets {
    my $self = shift;
    while ( @_ ) {
        my $header = shift;
        my $packet = shift;

        my $ether = NetPacket::Ethernet->decode($packet);
        next
            unless $ether->{type} && $ether->{type} == ETH_TYPE_IP;
        my $ip = NetPacket::IP->decode( $ether->{data} );
        next
            unless $ip->{proto} && $ip->{proto} == IP_PROTO_UDP;
        my $udp = NetPacket::UDP->decode( $ip->{data} );
        next
            unless $udp->{dest_port} == 28960;
        my $data = $udp->{data};
        next
            unless $data;

        # check for OOB packet marker
        if (not $data =~ s/\A\xff{4}//msx) {
            next;
        }

        $self->parse_packet($ip, $data);
    }
}

sub parse_packet {
    my $self = shift;
    my $ip = shift;
    my $data = shift;

    my $player_data;
    if ( $data =~ m{
        \A
        connect[ ][0-9a-f]+[ ]
        "\\([^"]+)"
    }msx ) {
        my $connect_data = $1;
        my %data = split /\\/, $connect_data;
        my $steam_id = $data{steamid};
        my $high_id = substr($steam_id, -8, 8, '');
        $steam_id = $high_id . ( 0 x (8 - length $steam_id) ) . $steam_id;
        $player_data = {
            action   => 'connect',
            ip       => $ip->{src_ip},
            name     => $data{name},
            steam_id => $steam_id,
        }
    }
    elsif ( $data =~ m{
        \A\d
        memberJoin[ ][^ ]*[ ]
        ([0-9a-f]{16})
        [ ]\w+\x00
        .{44}
        ([^\x00]+)
    }msx ) {
        $player_data = {
            action   => 'memberJoin',
            ip       => $ip->{src_ip},
            name     => $2,
            steam_id => $1,
        };
    }
    elsif ( $data =~ m{
        \A\d
        ident\x00
        ([^\x00]+)
    }msx ) {
        my $player_name = $1;
        $player_data = {
            action  => 'ident',
            ip      => $ip->{src_ip},
            name    => $1,
        }
    }
    if ($player_data) {
        my $callback = $self->{callback};
        my $w; $w = AE::idle(sub {
            undef $w;
            $callback->($player_data);
        });
    }
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
