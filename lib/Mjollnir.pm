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
#use Mjollnir::DB;

sub create {
    my $class = shift;
    my $device = shift;

    return POE::Session->create(
        inline_states => {
            _start          => \&_start,
            player_connect  => \&player_connect,
            player_join     => \&player_join,
            player_ident    => \&player_ident,
            request         => \&request,
            get_players     => \&get_players,
            ban_ip          => \&ban_ip,
        },
        args => [$device],
    );
}

sub _start {
    my ($kernel, $heap, $device) = @_[KERNEL, HEAP, ARG0];

    my $monitor = Mjollnir::Monitor->spawn($device);
    my $web = Mjollnir::Web->new($_[SESSION]);

    my $server = POE::Component::Server::PSGI->new(
        host => '127.0.0.1',
        port => 28900,
    );
    $heap->{players} = [];
    $server->register_service(sub { $web->run_psgi(@_) });
}

sub ban_ip {
    my ($kernel, $heap, $ip) = @_[KERNEL, HEAP, ARG0];

    `ipseccmd -n BLOCK -f $ip+0:28960:UDP`;
}

sub add_player {
    my ($players, $ip, $name) = @_;
    my %players = map { $_->{name} => $_->{ip} } @$players;
    if ($players{$name}) {
        for my $i (0..$#$players) {
            my $player = $players->[$i];
            if ($player->{name} eq $name) {
                splice @$players, $i, 1;
                last;
            }
        }
    }
    elsif (@$players >= 16) {
        my $oldest_player = pop @$players;
        delete $players{$oldest_player->{name}};
    }
    unshift @$players, {name => $name, ip => $ip};
    $players{$name} = 1;
}


sub player_connect {
    my ($kernel, $heap, $data) = @_[KERNEL, HEAP, ARG0];
    add_player($heap->{players}, $data->{ip}, $data->{name});
    print "connected $data->{ip} $data->{steam_id} $data->{name}\n";
}

sub player_join {
    my ($kernel, $heap, $data) = @_[KERNEL, HEAP, ARG0];
    add_player($heap->{players}, $data->{ip}, $data->{name});
    print "joined $data->{ip} $data->{steam_id} $data->{name}\n";
}

sub player_ident {
    my ($kernel, $heap, $data) = @_[KERNEL, HEAP, ARG0];
    add_player($heap->{players}, $data->{ip}, $data->{name});
    print "ident $data->{ip} $data->{name}\n";
}

sub get_players {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    return $heap->{players};
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