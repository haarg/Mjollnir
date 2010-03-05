package Mjollnir;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.01;

use POE;
use POE::Kernel;
use POE::Component::Server::PSGI;
use Mjollnir::Monitor;
use Mjollnir::Web;
use Mjollnir::DB;

sub create {
    my $class  = shift;
    my $device = shift;

    return POE::Session->create(
        package_states => [
            $class => [ qw(
                    _start
                    player_join
                    player_ident
                    get_players
                    ban_ip
                    ban_id
                    reload_bans
                    get_id_for_ip
                    get_names_for_id
                    get_ips_for_id
                    )
            ],
            $class => { player_connect => 'player_join', },
        ],
        args => [$device],
    );
}

sub _start {
    my ( $kernel, $heap, $device ) = @_[ KERNEL, HEAP, ARG0 ];

    my $monitor = Mjollnir::Monitor->spawn($device);
    my $web     = Mjollnir::Web->new( $_[SESSION] );

    my $server = POE::Component::Server::PSGI->new(
        host => '127.0.0.1',
        port => 28900,
    );
    $heap->{db} = Mjollnir::DB->new;
    $server->register_service( sub { $web->run_psgi(@_) } );

    $kernel->yield('reload_bans');
}

sub ban_ip {
    my ( $kernel, $heap, $ip, $id ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
    $heap->{db}->add_ip_ban( $ip, $id );
    `ipseccmd -n BLOCK -f $ip+0:28960:UDP`;
    return 1;
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

=head2 C<run ( [ $device ] )>

Runs Mjollnir, monitoring the given device.

=head1 AUTHOR

Graham Knop <haarg@haarg.org>

=head1 LICENSE

Copyright (c) 2010, Graham Knop
 
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0. For more details, see the
full text of the licenses in the directory LICENSES.

=cut
