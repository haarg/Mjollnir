package Mjollnir::Monitor;
use strict;
use warnings;
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
            shutdown => \&_shutdown,
            poll => \&_poll,
            got_packet => \&got_packet,
            connect => \&connect,
            member_join => \&member_join,
            ident => \&ident,
        },
        heap => {
            device => $device,
        },
    );
}

sub _start {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    my $device = $heap->{device};
    my $network_raw;
    my $mask_raw;
    my $err;
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

sub _poll {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    Net::Pcap::dispatch($heap->{pcap}, -1, sub {
        my (undef, $header, $packet) = @_;
        $kernel->yield( got_packet => $packet );
    }, 1);
    $heap->{timer} = $kernel->delay_set( 'poll', 0.5 );
}

sub _shutdown {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    warn "asdasd\n";
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
    if ($data =~ m{\bconnect [0-9a-f]+ "\\([^"]+)"}) {
        my $playerdata = $1;
        my %data = split /\\/, $playerdata;
        $kernel->yield( 'connect', $ip->{src_ip}, \%data );
    }
    elsif ($data =~ /^\xff{4}0memberJoin [^ ]* ([0-9a-f]{8})([0-9a-f]{8})/) {
        my $steam_id = $2 . $1;
        $kernel->yield( 'member_join', $ip->{src_ip}, $steam_id );
    }
    elsif ($data =~ /^\xff{4}0ident\x00([^\x00]+)/) {
        my $player_name = $1;
        $kernel->yield( 'ident', $ip->{src_ip}, $player_name );
    }
#    elsif ($data =~ /partystate/) {
#    }
}

sub connect {
    my ($kernel, $heap, $ip, $data) = @_[KERNEL, HEAP, ARG0, ARG1];
    print "connected $ip $data->{steamid} $data->{name} \n";
}

sub member_join {
    my ($kernel, $heap, $ip, $steam_id) = @_[KERNEL, HEAP, ARG0, ARG1];
    print "joined $ip $steam_id\n";
}

sub ident {
    my ($kernel, $heap, $ip, $player_name) = @_[KERNEL, HEAP, ARG0, ARG1];
    print "ident $ip $player_name\n";
}

1;