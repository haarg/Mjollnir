package Mjollnir::Web;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.03;

use POE;
use POE::Kernel;
use Plack::Request;
use Template;
use File::ShareDir ();
use File::Spec;
use POE::Component::Server::PSGI;
use Math::BigInt;

sub spawn {
    my $class = shift;
    my $listen = shift // '127.0.0.1:28900';

    return POE::Session->create(
        args => [ $listen ],
        inline_states => {
            _start => sub {
                my ( $heap, $parent, $listen ) = @_[HEAP, SENDER, ARG0];
                my $web = $class->new( $parent->ID );
                my $app = sub { $web->run_psgi(@_) };
                my ($host, $port) = split /:/, $listen;
                my $server = POE::Component::Server::PSGI->new(
                    host => $host,
                    port => $port,
                );
                open my $olderr, '>&', STDERR;
                open STDERR, '>', File::Spec->devnull;
                $heap->{web_session} = $server->register_service( $app );
                open STDERR, '>&', $olderr;
                close $olderr;
                print "Listening for HTTP connections:\n\t$listen\n";
            },
            shutdown => sub {
                my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
                $kernel->post(delete $heap->{web_session}, 'shutdown');
                print "Stopping web server.\n";
                return 1;
            },
        },
    );
}

sub new {
    my $class    = shift;
    my $manager  = shift;
    my $self = bless {
        manager  => $manager,
    }, $class;
    $self->{template} = Template->new(
        INCLUDE_PATH => File::Spec->catdir(
            File::ShareDir::dist_dir('Mjollnir'), 'templates'
        ),
        DELIMITER => ( $^O eq 'MSWin32' ? ';' : ':' ),
        FILTERS => {
            format_name => [ sub {
                my $context = shift;
                return sub {
                    my $name = shift;
                    my @parts = $self->name_parts($name);
                    my $template = $context->template('format_name');
                    my $output = $context->process($template, {
                        raw_name => $name,
                        segments => \@parts,
                    });
                    return $output;
                };
            }, 1],
        },
    );
    return $self;
}

sub run_psgi {
    my $self = shift;
    my $env  = shift;
    my $req  = Plack::Request->new($env);

    my $path_info = $req->path_info;
    my (undef, $command, $data) = split m{/}, $path_info, 3;
    
    if ($command eq '') {
        return $self->www_main($req);
    }
    my $call_method = 'www_' . $command;
    if ($self->can($call_method)) {
        return $self->$call_method($req, $data);
    }
    return [404, ['Content-Type' => 'text/plain'], ['Not found']];
}

sub www_main {
    my $self = shift;
    my $req  = shift;

    my $param = $req->parameters;
    my $vars = { param => $param };
    if ( $param->{op} && $param->{op} eq 'ban' ) {
        my $ban_data = $vars->{ban_data} = {};
        if ( my $ip = $param->{ip} ) {
            $ban_data->{ips} = [ $param->get_one('ip') ];
            my $id = $self->db->get_id_for_ip($ip);
            $ban_data->{names} = $self->db->get_names($id);
            if ( $param->{confirm} ) {
                $ban_data->{result}
                    = $self->ban_ip( $param->get_one('ip') );
            }
        }
        elsif ( my $id = $param->{id} ) {
            $ban_data->{id}    = $id;
            $ban_data->{ips}   = $self->db->get_ips( $id );
            $ban_data->{names} = $self->db->get_names( $id );
            if ( $param->{confirm} ) {
                $ban_data->{result} = $self->ban_id( $param->{id} );
            }
        }
    }

    $vars->{player_list} = $self->get_players;
    $vars->{refresh}     = $req->request_uri;
    $vars->{post_uri}    = $req->base;

    my $res = $req->new_response(200);
    $res->content_type('text/html; charset=utf-8');

    my $content = '';
    $self->{template}->process( 'main', $vars, \$content );
    $res->body($content);
    return $res->finalize;
}

sub www_player {
    my $self = shift;
    my $req  = shift;
    my $player = shift;

    my $res = $req->new_response(200);
    $res->content_type('text/html; charset=utf-8');

    my $vars = {
        id      => $player,
        ips     => [ map { {
            ip      => $_,
            banned  => $self->db->check_banned_ip($_),
        } } @{ $self->db->get_ips($player) } ],
        names   => $self->db->get_names($player),
        banned  => $self->db->check_banned_id($player),
        community_link => $self->community_link_for_id($player),
    };
    my $content = '';
    $self->{template}->process( 'player', $vars, \$content );

    $res->body($content);
    return $res->finalize;
}

sub www_bans {
    my $self = shift;
    my $req  = shift;

    my $param = $req->parameters;
    my $res = $req->new_response(200);
    $res->content_type('text/html; charset=utf-8');

    my $vars = {
        ips     => $self->db->get_ip_bans,
        ids     => $self->db->get_id_bans,
        names   => $self->db->get_name_bans,
    };
    my $content = '';
    $self->{template}->process( 'bans', $vars, \$content );

    $res->body($content);
    return $res->finalize;
}

sub get_players {
    my $self = shift;
    return $self->db->get_latest_players;
}

sub db {
    my $self = shift;
    return POE::Kernel->call( $self->{manager}, 'db' );
}

sub ban_id {
    my $self = shift;
    return POE::Kernel->call( $self->{manager}, 'ban_id', @_ );
}

sub ban_ip {
    my $self = shift;
    return POE::Kernel->call( $self->{manager}, 'ban_ip', @_ );
}

sub name_parts {
    my $self = shift;
    my $name = shift;
    my @colors = qw(black red green yellow blue cyan pink white grey other);
    my @outparts;
    my @parts = split /\^(\d)/, $name;
    unshift @parts, undef;
    while (@parts) {
        my $color = shift @parts;
        my $segment = shift @parts;
        next
            if $segment eq '';
        push @outparts, {
            raw => defined $color ? '^' . $color . $segment : $segment,
            color_code => $color,
            text => $segment,
            color => defined $color ? $colors[$color] : undef,
        };
    }
    return @outparts;
}

sub community_link_for_id {
    my $self = shift;
    my $steam_id = shift;
    my $dec_id = Math::BigInt->from_hex('0x' . $steam_id)->bstr;
    my $link = 'http://steamcommunity.com/profiles/' . $dec_id . '/';
    return $link;
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
