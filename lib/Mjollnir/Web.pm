package Mjollnir::Web;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.03;

use POE;
use POE::Kernel;
use POE::Component::Server::PSGI;
use Plack::Request;
use Plack::MIME;
use Template;
use File::ShareDir ();
use File::Spec;
use Mjollnir::Player;

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
                    my $parts = $self->_segment_name($name);
                    my $template = $context->template('format_name');
                    my $output = $context->process($template, {
                        raw_name => $name,
                        segments => $parts,
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
    my $filepath = File::Spec->catfile(File::ShareDir::dist_dir('Mjollnir'), 'templates', $path_info);
    if ( -e $filepath ) {
        my $filename = $path_info;
        $filename =~ s{\A/}{}msx;
        my $vars = { param => $req->parameters };
        my $mime = Plack::MIME->mime_type($filename) || 'text/plain';
        if ($mime =~ m{\Atext/}) {
            $mime .= '; charset=utf-8';
        }
        return sub {
            my $respond = shift;
            my $writer = $respond->([200, ['Content-Type' => $mime]]);
            $self->process_template( $filename, $vars, $writer );
            return;
        };
    }
    return [404, ['Content-Type' => 'text/plain'], ['Not found']];
}

sub www_main {
    my $self = shift;
    my $req  = shift;

    my $db = $self->db;
    my $param = $req->parameters;
    my $vars = { param => $param };
    if ( my $id = $param->{kick} ) {
        my $kick_data = $vars->{kick} = {};
        my $player = $kick_data->{player} = Mjollnir::Player->new($db, $id);
        if ( $param->{confirm} ) {
            $kick_data->{result}
                = $param->{ban} ? $player->ban($param->{reason})
                                : $player->kick
                                ;
        }
    }

    $vars->{players}    = Mjollnir::Player->find_latest($db);
    $vars->{refresh}    = $req->request_uri;
    $vars->{post_uri}   = $req->base;

    my $res = $req->new_response(200);
    $res->content_type('text/html; charset=utf-8');
    $res->body( $self->process_template('main', $vars) );
    return $res->finalize;
}

sub www_player {
    my $self = shift;
    my $req  = shift;
    my $player_id = shift;

    my $db = $self->db;
    my $player = Mjollnir::Player->new($db, $player_id);

    my $param = $req->parameters;
    my $res = $req->new_response(200);
    $res->content_type('text/html; charset=utf-8');

    $player->refresh;
    my $vars = {
        player  => $player,
        check_banned_ip => sub { $db->check_banned_ip(@_) },
        param => $param,
    };
    
    if ($param->{unban} && $param->{confirm}) {
        $vars->{unban}{result} = $player->unban;
    }

    $res->body( $self->process_template( 'player', $vars ) );
    return $res->finalize;
}

sub www_bans {
    my $self = shift;
    my $req  = shift;

    my $param = $req->parameters;
    my $res = $req->new_response(200);
    $res->content_type('text/html; charset=utf-8');

    my $db = $self->db;

    my $vars = {};
    if ( $param->{ban_name} ) {
        $vars->{name_ban}{result} = $db->add_name_ban($param->{ban_name});
        $vars->{name_ban}{name} = $param->{ban_name};
    }
    if ( $param->{unban_name} ) {
        $vars->{name_unban}{result} = $db->remove_name_ban($param->{unban_name});
        $vars->{name_unban}{name} = $param->{unban_name};
    }
    $vars->{players} = Mjollnir::Player->find_banned($db);
    $vars->{ips}     = $db->get_ip_bans;
    $vars->{names}   = $db->get_name_bans;

    $res->body( $self->process_template( 'bans', $vars ) );
    return $res->finalize;
}

sub www_search {
    my $self = shift;
    my $req  = shift;

    my $param = $req->parameters;
    my $search = $param->{q};
    my $res = $req->new_response;
    if (!defined $search || $search eq '') {
        $res->redirect($req->base);
        return $res->finalize;
    }

    return sub {
        my $respond = shift;

        my $db = $self->db;
        my $player;
        if ( $search =~ m{\Ahttp://(?:www\.)?steamcommunity.com/}msx ) {
            $player = Mjollnir::Player->new_by_link($db, $search);
        }
        elsif ( $search =~ /\A[0-9a-zA-Z]{16}\z/ ) {
            $player = Mjollnir::Player->new($db, $search);
        }
        else {
            my $players;
            if ( $search =~ /\A(?:\d+[.]){3}\d+\z/ ) {
                $players = Mjollnir::Player->find_by_ip($db, $search);
            }
            else {
                $players = Mjollnir::Player->find_by_name($db, $search);
            }
            if (@$players == 1) {
                $player = $players->[0];
            }
            else {
                my $vars = {
                    players => $players,
                    param => $param,
                };
                my $writer = $respond->([200, ['Content-Type' => 'text/html; charset=utf-8']]);
                $self->process_template('search', $vars, $writer);
                return;
            }
        }
        if ($player) {
            $res->redirect($req->base . 'player/' . $player->id);
            $respond->($res->finalize);
            return;
        }
    };
}

sub db {
    my $self = shift;
    return POE::Kernel->call( $self->{manager}, 'db' );
}

sub process_template {
    my $self = shift;
    my $template = shift;
    my $vars = shift;
    my $write = shift;
    if ($write) {
        my $o = Plack::Util::inline_object(
            print => sub { $write->write(@_) },
        );
        $self->{template}->process( $template, $vars, $o );
        $write->close;
        return;
    }
    else {
        my $content = '';
        $self->{template}->process( $template, $vars, \$content )
            or die $self->{template}->error;
        return $content;
    }
}

my @name_colors = qw(black red green yellow blue cyan pink white grey other);
sub _segment_name {
    my $self = shift;
    my $name = shift;
    my @outparts;
    my @parts = split /\^(\d)/, $name;
    unshift @parts, undef;
    while (@parts) {
        my $color = shift @parts;
        my $segment = shift @parts;
        $segment //= '';
        push @outparts, {
            text => $segment,
            defined $color ? (
                raw         => '^' . $color . $segment,
                color       => $name_colors[$color],
                color_code  => $color,
            ) : (
                raw         => $segment,
            ),
        };
    }
    return \@outparts;
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
