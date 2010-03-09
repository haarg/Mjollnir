package Mjollnir;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.01;

use POE;
use POE::Kernel;
use Mjollnir::Monitor;
use Mjollnir::LogMonitor;
use Mjollnir::Web;
use Mjollnir::DB;
use Mjollnir::IPBan;

sub create {
    my $class  = shift;

    return POE::Session->create(
        package_states => [
            $class => [ qw(
                    _start
                    shutdown
                    exit_signal
                    player_join
                    player_ident
                    get_players
                    ban_ip
                    ban_id
                    reload_bans
                    get_id_for_ip
                    get_names_for_id
                    get_ips_for_id
                    get_id_for_ip
                    get_ip_bans
                    get_id_bans
                    check_banned_ip
                    check_banned_id
                    )
            ],
            $class => { player_connect => 'player_join' },
        ],
        args => [@_],
    );
}

sub _start {
    my ( $kernel, $heap, %config ) = @_[ KERNEL, HEAP, ARG0..$#_ ];
    $heap->{db}             = Mjollnir::DB->new;

    $heap->{log_monitor}    = Mjollnir::LogMonitor->spawn($config{log_file});
    $heap->{net_monitor}    = Mjollnir::Monitor->spawn($config{device});
    $heap->{web_server}     = Mjollnir::Web->spawn($config{listen});

    $kernel->sig($_, 'exit_signal')
        for qw(INT QUIT TERM HUP);
}

sub exit_signal {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $kernel->sig_handled;
    $kernel->sig($_)
        for qw(INT QUIT TERM HUP);
    $kernel->yield('shutdown');
}

sub shutdown {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    for (qw(log_monitor net_monitor web_server)) {
        $kernel->call(delete $heap->{$_}, 'shutdown')
    }
    $kernel->yield('clear_active_bans');
}

sub ban_ip {
    my ( $kernel, $heap, $ip, $id ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
    $heap->{db}->add_ip_ban( $ip, $id );
    return Mjollnir::IPBan::ban_ip($ip);
}

sub ban_id {
    my ( $kernel, $heap, $id ) = @_[ KERNEL, HEAP, ARG0 ];
    $heap->{db}->add_id_ban($id);
    my $ips = $heap->{db}->get_ips($id);
    $kernel->yield( ban_ip => $_, $id ) for @$ips;
    return 1;
}

sub player_join {
    my ( $kernel, $heap, $data ) = @_[ KERNEL, HEAP, ARG0 ];
    $heap->{db}->add_name( $data->{steam_id}, $data->{name} );
    $heap->{db}->add_ip( $data->{steam_id}, $data->{ip} );
    if ( $heap->{db}->check_banned_id( $data->{id} ) ) {
        $kernel->yield( ban_ip => $data->{ip} );
    }
    print "join\t$data->{steam_id}\t$data->{ip}\t$data->{name}\n";
}

sub player_ident {
    my ( $kernel, $heap, $data ) = @_[ KERNEL, HEAP, ARG0 ];
    my $id = $heap->{db}->get_id_for_ip( $data->{id} );
    $heap->{db}->add_name( $id, $data->{name} );
    print "ident\t$id\t$data->{ip}\t$data->{name}\n";
}

sub get_players {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    return $heap->{db}->get_latest_players;
}

sub get_id_for_ip {
    my ( $kernel, $heap, $ip ) = @_[ KERNEL, HEAP, ARG0 ];
    return $heap->{db}->get_id_for_ip($ip);
}

sub get_names_for_id {
    my ( $kernel, $heap, $id ) = @_[ KERNEL, HEAP, ARG0 ];
    return $heap->{db}->get_names($id);
}

sub get_ips_for_id {
    my ( $kernel, $heap, $id ) = @_[ KERNEL, HEAP, ARG0 ];
    return $heap->{db}->get_ips($id);
}

sub check_banned_id {
    my ( $kernel, $heap, $id ) = @_[ KERNEL, HEAP, ARG0 ];
    return $heap->{db}->check_banned_id($id);
}

sub check_banned_ip {
    my ( $kernel, $heap, $ip ) = @_[ KERNEL, HEAP, ARG0 ];
    return $heap->{db}->check_banned_ip($ip);
}

sub get_ip_bans {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    return $heap->{db}->get_ip_bans;
}

sub get_id_bans {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    return $heap->{db}->get_id_bans;
}

sub reload_bans {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
}

sub run {
    shift->create(@_);
    POE::Kernel->run;
}

1;

__END__

=head1 NAME

Mjollnir - Modern Warfare 2 Ban Hammer

=head1 SYNOPSIS

use Mjollnir;

Mjollnir->run($device);

=head1 DESCRIPTION

Modern Warfare 2 Ban Hammer

=head1 METHODS

=head2 C<run>

Runs Mjollnir, monitoring the given device.

=head1 AUTHOR

Graham Knop <haarg@haarg.org>

=head1 LICENSE

Copyright (c) 2010, Graham Knop
 
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0. For more details, see the
full text of the licenses in the directory LICENSES.

=cut
