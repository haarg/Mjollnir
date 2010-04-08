package Mjollnir;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.04;

use AnyEvent;
use Mjollnir::Monitor;
use Mjollnir::Web;
use Mjollnir::DB;
use Mjollnir::IPBan;
use Mjollnir::Player;
use POSIX ();

sub new {
    my $class = shift;
    my $options  = (@_ == 1 && ref $_[0]) ? shift : { @_ };
    my $self = bless {
        config => $options,
    }, $class;
    return $self;
}

sub run {
    my $self = ref $_[0] ? shift : shift->new(@_);
    return $self->start->recv;
}

sub start {
    my $self = shift;
    print "Starting Mjollnir...\n";

    $self->{signal_watchers} = {};
    for my $sig (qw(INT QUIT TERM HUP)) {
        $self->{signal_watchers}{$sig} = AnyEvent->signal(
            signal  => $sig,
            cb      => sub { $self->shutdown },
        );
    }

    # this seems to fix catching signals on Windows
    { my %sig = %SIG }

    $self->{net_monitor} = Mjollnir::Monitor->new(
        %{ $self->{config} },
        callback => sub { $self->player_action(@_) },
    )->start;
    $self->{web_server} = Mjollnir::Web->new(
        %{ $self->{config} },
        db => $self->db,
    )->start;

    $self->clear_ip_bans;

    $self->{cv} = AnyEvent->condvar;
    return $self->{cv};
}

sub shutdown {
    my $self = shift;
    print "Shutting down...\n";
    delete $self->{signal_watchers};
    if (my $net_monitor = delete $self->{net_monitor}) {
        $net_monitor->shutdown;
    }
    if (my $web_server = delete $self->{web_server}) {
        $web_server->shutdown;
    }
    $self->clear_ip_bans;
    $self->{cv}->send;
}

sub db {
    my $self = shift;
    $self->{db} ||= Mjollnir::DB->new($self->{config});
    return $self->{db};
}

sub clear_ip_bans {
    my $self = shift;
    $self->db->clear_ip_bans;
    Mjollnir::IPBan::clear_bans();
    return 1;
}

sub player_action {
    my $self = shift;
    my $data = shift;
    my $player;
    if ($data->{steam_id}) {
        $player = Mjollnir::Player->new($self->db, $data->{steam_id});
    }
    elsif ($data->{ip}) {
        $player = Mjollnir::Player->new_by_ip($self->db, $data->{ip});
    }
    if ( $data->{name} ) {
        $player->add_name( $data->{name} );
    }
    if ( $data->{ip} ) {
        $player->add_ip( $data->{ip} );
    }
    $player->validate;
    print join("\t", POSIX::strftime("[%d/%b/%Y %H:%M:%S]", localtime), $player->id, $player->ip, $player->name) . "\n";
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
