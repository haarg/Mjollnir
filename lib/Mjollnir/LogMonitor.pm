package Mjollnir::LogMonitor;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.01;

use POE;
use POE::Session;
use POE::Wheel::FollowTail;
use File::Spec;

sub detect_log_file {
    eval { require Win32API::Registry }
        or die "Unable to find log file.\n";

    my $key;
    Win32API::Registry::RegOpenKeyEx( Win32API::Registry::HKEY_LOCAL_MACHINE(), "SOFTWARE\\Activision\\Modern Warfare 2", 0, Win32API::Registry::KEY_READ(), $key )
        or return;
    Win32API::Registry::RegQueryValueEx( $key, 'InstallPath', [], my $type, my $path, [] )
        or return;
    Win32API::Registry::RegCloseKey( $key );
    $path =~ s/\x00//g;
    my $log_file = File::Spec->catfile($path, 'main', 'games_mp.log');
    return $log_file
        if -e $log_file;
    die "Unable to find log file.\n";
}

sub spawn {
    my $class  = shift;
    my $log_file = shift // detect_log_file();
    return POE::Session->create(
        args => [ $log_file ],
        package_states => [
            $class => [qw(
                _start
                shutdown
                got_log_line
                weapon
                kill
                death
                message
                messageteam
                join
                quit
                startgame
                endgame
                stopgame
            )],
        ],
    );
}

sub _start {
    my ( $kernel, $heap, $log_file) = @_[KERNEL, HEAP, ARG0];
    $heap->{tail} = POE::Wheel::FollowTail->new(
        Filename => $log_file,
        InputEvent => 'got_log_line',
    );
    $heap->{target_session} = $_[SENDER]->ID;
    print "Monitoring log file:\n\t$log_file\n";
}

sub shutdown {
    my ( $kernel, $heap ) = @_[KERNEL, HEAP ];
    delete $heap->{tail};
    delete $heap->{target_session};
    print "Stopping log monitor.\n";
}

my %event_dispatch = (
    Weapon                  => 'weapon',
    K                       => 'kill',
    D                       => 'death',
    say                     => 'message',
    sayteam                 => 'messageteam',
    J                       => 'join',
    Q                       => 'quit',
    'ExitLevel: executed'   => 'endgame',
    'ShutdownGame:'         => 'stopgame',
    'InitGame'              => 'startgame',
);
sub got_log_line {
    my ( $kernel, $heap, $line ) = @_[KERNEL, HEAP, ARG0];
    if ($line =~ /\A\s*(\d+:\d+) (.*)\z/) {
        my $time = $1;
        my $event_string = $2;
        my @event_data = split /;/, $event_string;
        my $event = shift @event_data;
        if (my $dispatch = $event_dispatch{$event}) {
            $kernel->yield($dispatch, @event_data);
        }
    }
}

sub kill {
    my ( $kernel, $heap, $victim_steam_id, undef, $victim_team, $victim_name, $steam_id, undef, $team, $name, $weapon, undef, $damage_type, $body_part) = @_[KERNEL, HEAP, ARG0..$#_];
}
sub death {
    my ( $kernel, $heap, $victim_steam_id, undef, $victim_team, $victim_name, $steam_id, undef, $team, $name, $weapon, undef, $damage_type, $body_part) = @_[KERNEL, HEAP, ARG0..$#_];
}

sub weapon {
    my ( $kernel, $heap, $steam_id, undef, $name, $weapon ) = @_[KERNEL, HEAP, ARG0..$#_];
}

sub message {
    my ( $kernel, $heap, $steam_id, undef, $name, $message ) = @_[KERNEL, HEAP, ARG0..$#_];
    $message =~ s/^\x15//;
}

sub messageteam {
    my ( $kernel, $heap, $steam_id, undef, $name, $message ) = @_[KERNEL, HEAP, ARG0..$#_];
    $message =~ s/^\x15//;
}

sub startgame {
    my ( $kernel, $heap ) = @_[KERNEL, HEAP];
}

sub endgame {
    my ( $kernel, $heap ) = @_[KERNEL, HEAP];
}

sub stopgame {
    my ( $kernel, $heap ) = @_[KERNEL, HEAP];
}

sub join {
    my ( $kernel, $heap, $steam_id, undef, $name ) = @_[KERNEL, HEAP, ARG0..$#_];
    warn "$steam_id joined as $name\n";
}

sub quit {
    my ( $kernel, $heap, $steam_id, undef, $name ) = @_[KERNEL, HEAP, ARG0..$#_];
    warn "$steam_id quit as $name\n";
}

1;

__END__

=head1 NAME

Mjollnir::LogMonitor - Log monitor for Mjollnir

=head1 AUTHOR

Graham Knop <haarg@haarg.org>

=head1 LICENSE

Copyright (c) 2010, Graham Knop
 
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0. For more details, see the
full text of the licenses in the directory LICENSES.

=cut
