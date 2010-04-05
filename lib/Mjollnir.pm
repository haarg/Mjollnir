package Mjollnir;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.03;

use POE;
use POE::Kernel;
use Mjollnir::Monitor;
use Mjollnir::Web;
use Mjollnir::DB;
use Mjollnir::IPBan;
use Mjollnir::Player;

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
                db
                clear_ip_bans
            ) ],
            $class => { player_connect => 'player_join' },
        ],
        args => [@_],
    );
}

sub _start {
    my ( $kernel, $heap, %config ) = @_[ KERNEL, HEAP, ARG0..$#_ ];
    print "Starting Mjollnir...\n";
    $heap->{db}             = Mjollnir::DB->new;

    $heap->{net_monitor}    = Mjollnir::Monitor->spawn($config{device});
    $heap->{web_server}     = Mjollnir::Web->spawn($config{listen});

    for my $sig (qw(INT QUIT TERM HUP)) {
        $kernel->sig($sig, 'exit_signal');
    }
    $kernel->yield('clear_ip_bans');
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
    $kernel->yield('clear_ip_bans');
}

sub clear_ip_bans {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $heap->{db}->clear_ip_bans;
    return Mjollnir::IPBan::clear_bans();
}

sub player_join {
    my ( $kernel, $heap, $data ) = @_[ KERNEL, HEAP, ARG0 ];
    my $player = Mjollnir::Player->new($heap->{db}, $data->{steam_id});
    $player->add_name( $data->{name} );
    $player->add_ip( $data->{ip} );
    $kernel->yield(check_user => $player);
    print join("\t", time, 'join', $player->id, $player->ip, $player->name) . "\n";
}

sub player_ident {
    my ( $kernel, $heap, $data ) = @_[ KERNEL, HEAP, ARG0 ];
    my $player = Mjollnir::Player->new_by_ip($heap->{db}, $data->{ip});
    my $id = $player->id;
    $player->add_name( $data->{name} );
    $kernel->yield(check_user => $player);
    print join("\t", time, 'ident', $player->id, $player->ip, $player->name) . "\n";
}

sub check_user {
    my ( $kernel, $heap, $player ) = @_[ KERNEL, HEAP, ARG0 ];
    $player->refresh;
    if ( $player->is_banned || $player->is_name_banned ) {
        $player->kick;
    }
    elsif ( $player->vac_banned ) {
        $player->ban('VAC banned');
    }
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
