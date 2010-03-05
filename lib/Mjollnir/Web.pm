package Mjollnir::Web;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.01;

use POE::Kernel;
use Plack::Request;
#use Mjollnir::DB;
#use Template;

sub new {
    my $class = shift;
    my $manager = shift;
    my $self = bless {
        manager => $manager,
    }, $class;
    return $self;
}

sub run_psgi {
    my $self = shift;
    my $env = shift;
    my $req = Plack::Request->new($env);

    my $res = $req->new_response(200);
    $res->content_type('text/html');
    my $output = <<"END_HTML";
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
    <head>
        <title>Mjöllnir Web</title>
    </head>
    <style type="text/css">
        .banned * {
            text-decoration: line-through;
        }
    </style>
    <body>
END_HTML
    if ($req->parameters->{ban_confirm}) {
        $output .= $self->ban_confirm_message($req->parameters->{ban_confirm});
    }
    elsif ($req->parameters->{ban}) {
        my $ip = $req->parameters->{ban};
        $self->ban_ip($ip);
        $output .= $self->ban_message($ip);
    }
    $output .= $self->generate_table;
    unless ($req->parameters->{ban_confirm}) {
        $output .= <<"END_HTML";
            <script type="text/javascript">
                window.setTimeout(function () {
                    document.location = './';
                }, 20000);
            </script>
END_HTML
    }
    $output .= <<"END_HTML";
    </body>
</html>
END_HTML
    $res->body($output);
    return $res->finalize;
}

sub generate_table {
    my $self = shift;
    my $output = <<"END_HTML";
        <table>
            <thead>
                <tr><th>#</th><th>Player</th><th>IP</th><th>Control</th>
            </thead>
            <tbody>
END_HTML
    my $i = 0;
    my $players = $self->get_players;
    my $bans = $self->{bans};
    for my $player (@$players) {
        my $banned = $bans->{$player->{ip}};
        $i++;
        $output .= qq{<tr};
        if ($banned) {
            $output .= ' class="banned"';
        }
        $output .= qq{><td>$i</td><td>$player->{name}</td><td>$player->{ip}</td><td>};
        unless ($banned) {
            $output .= qq{<a href="?ban_confirm=$player->{ip}">Ban</a>};
        }
        $output .= qq{</td></tr>};
    }
    $output .= <<"END_HTML";
            </tbody>
        </table>
END_HTML
    return $output;
}

sub ban_confirm_message {
    my $self = shift;
    my $ip = shift;
    my $player_names = join ', ', map { $_->{name} } $self->players_for_ip($ip);
    my $output = "<h1>Are you sure you want to ban $ip ($player_names)?</h1>";
    $output .= qq{<h2><a href="?ban=$ip">Yes</a> <a href="./">No</a></h2>};
    return $output;
}

sub ban_message {
    my $self = shift;
    my $ip = shift;
    my $player_names = join ', ', map { $_->{name} } $self->players_for_ip($ip);
    my $output = "<h1>$ip ($player_names) has been banned</h1>";
    return $output;
}

sub players_for_ip {
    my $self = shift;
    my $ip = shift;
    my $players = $self->get_players;
    my @matched_players = grep { $_->{ip} eq $ip } @{ $players };
    return @matched_players;
}

sub ban_ip {
    my $self = shift;
    my $ip_address = shift;
    $self->{bans}{$ip_address} = 1;
    $self->post(ban_ip => $ip_address);
    return 1;
}

sub post {
    my $self = shift;
    POE::Kernel->post($self->{manager}, @_);
}

sub get_players {
    my $self = shift;
    return $self->call('get_players');
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