package Mjollnir::Web;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.01;

use POE::Kernel;
use Plack::Request;
use Template;
use File::ShareDir ();
use File::Spec;

sub new {
    my $class = shift;
    my $manager = shift;
    my $template = Template->new(
        INCLUDE_PATH => File::Spec->catdir(File::ShareDir::dist_dir('Mjollnir'), 'templates'),
        DELIMITER => ';',
    );
    my $self = bless {
        manager => $manager,
        template => $template,
    }, $class;
    return $self;
}

sub run_psgi {
    my $self = shift;
    my $env = shift;
    my $req = Plack::Request->new($env);

    return $self->www_main($req);
}

sub www_main {
    my $self = shift;
    my $req = shift;

    my $param = $req->parameters;
    my $vars = {
        param => $param,
    };
    if ($param->{op} && $param->{op} eq 'ban') {
        my $ban_data = $vars->{ban_data} = {};
        if (my $ip = $param->{ip}) {
            $ban_data->{ips} = [ $param->get_one('ip') ];
            my $id = $self->call('get_id_for_ip', $ip);
            $ban_data->{names} = $self->call('get_names_for_id', $id);
            if ($param->{confirm}) {
                $ban_data->{result} = $self->call(ban_ip => $param->get_one('ip'));
            }
        }
        elsif (my $id = $param->{id}) {
            $ban_data->{id} = $id;
            $ban_data->{ips} = $self->call('get_ips_for_id', $id);
            $ban_data->{names} = $self->call('get_names_for_id', $id);
            if ($param->{confirm}) {
                $ban_data->{result} = $self->call(ban_id => $param->{id});
            }
        }
    }

    $vars->{player_list} = $self->get_players;
    $vars->{refresh} = $req->request_uri;
    $vars->{post_uri} = $req->base;

    my $res = $req->new_response(200);
    $res->content_type('text/html; charset=utf-8');

    my $content = '';
    $self->{template}->process('main', $vars, \$content);

    $res->body($content);
    return $res->finalize;
}

sub get_players {
    my $self = shift;
    return $self->call('get_players');
}

sub post {
    my $self = shift;
    POE::Kernel->post($self->{manager}, @_);
}

sub call {
    my $self = shift;
    return POE::Kernel->call($self->{manager}, @_);
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