package Mjollnir;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.02;

use POE;
use POE::Kernel;
use Mjollnir::Monitor;
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
                ban_ip
                ban_id
                reload_bans
                db
            ) ],
            $class => { player_connect => 'player_join' },
        ],
        args => [@_],
    );
}

sub _start {
    my ( $kernel, $heap, %config ) = @_[ KERNEL, HEAP, ARG0..$#_ ];
    $heap->{db}             = Mjollnir::DB->new;

    $heap->{net_monitor}    = Mjollnir::Monitor->spawn($config{device});
    $heap->{web_server}     = Mjollnir::Web->spawn($config{listen});

    for my $sig (qw(INT QUIT TERM HUP)) {
        $kernel->sig($sig, 'exit_signal');
    }
}

sub exit_signal {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $kernel->sig_handled;
    for my $sig (qw(INT QUIT TERM HUP)) {
        $kernel->sig($sig);
    }
    $kernel->yield('shutdown');
}

sub shutdown {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    print "Shutting down...\n";
    for my $child (qw(net_monitor web_server)) {
        $kernel->call(delete $heap->{$child}, 'shutdown')
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

sub reload_bans {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
}

sub run {
    shift->create(@_);
    POE::Kernel->run;
}

sub db {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    return $heap->{db};
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
