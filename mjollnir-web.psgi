package Mjollnir;
use strict;
use warnings;

use Plack::Request;
use Getopt::Long ();
use File::Spec;

Getopt::Long::GetOptions(
    'l|log=s' => \(my $log_file),
);

if (!$log_file) {
    $log_file = File::Spec->catpath((File::Spec->splitpath(__FILE__))[0,1] , 'mw2players.log');
    print "Reading log file $log_file\n";
}

sub new {
    my $class = shift;
    my $self = bless {
        bans => [],
    }, $class;
    return $self;
}

sub run_psgi {
    my $self = shift;
    my $env = shift;
    my $req = Plack::Request->new($env);

    my $path_info = $req->path_info;
    my $query     = $req->param('query');

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
    my $players = $self->read_logs;
    if ($req->parameters->{ban_confirm}) {
        $output .= $self->ban_confirm_message($req->parameters->{ban_confirm}, $players);
    }
    elsif ($req->parameters->{ban}) {
        my $ip = $req->parameters->{ban};
        $self->ban_ip($ip);
        $output .= $self->ban_message($ip, $players);
    }
    $output .= $self->generate_table($players);
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
    my $players = shift;
    my %bans = map { $_ => 1 } @{ $self->{bans} };
    my $output = <<"END_HTML";
        <table>
            <thead>
                <tr><th>#</th><th>Player</th><th>IP</th><th>Control</th>
            </thead>
            <tbody>
END_HTML
    my $i = 0;
    for my $player (@$players) {
        my $banned = $bans{$player->{ip}};
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
    my $players = shift;
    my $player_names = join ', ', map { $_->{name} } $self->players_for_ip($ip, $players);
    my $output = "<h1>Are you sure you want to ban $ip ($player_names)?</h1>";
    $output .= qq{<h2><a href="?ban=$ip">Yes</a> <a href="./">No</a></h2>};
    return $output;
}

sub ban_message {
    my $self = shift;
    my $ip = shift;
    my $players = shift;
    my $player_names = join ', ', map { $_->{name} } $self->players_for_ip($ip, $players);
    my $output = "<h1>$ip ($player_names) has been banned</h1>";
    return $output;
}

sub players_for_ip {
    my $self = shift;
    my $ip = shift;
    my $players = shift;
    my @matched_players = grep { $_->{ip} eq $ip } @{ $players };
    return @matched_players;
}

sub ban_ip {
    my $self = shift;
    my $ip_address = shift;
    `ipseccmd -n BLOCK -f $ip_address=0:28960:UDP`;
    push @{$self->{bans}}, $ip_address;
    return 1;
}

sub read_logs {
    my $self = shift;
    my $limit = shift // 16;
    open my $fh, '<', $log_file;
    my @players;
    my %players;
    while ( my $line = <$fh> ) {
        chomp $line;
        my ($ip, $name) = split /\t/, $line, 2;
        if ($players{$name}) {
            for my $i (0..$#players) {
                my $player = $players[$i];
                if ($player->{name} eq $name) {
                    splice @players, $i, 1;
                    last;
                }
            }
        }
        elsif ($limit && @players >= $limit) {
            my $oldest_player = pop @players;
            delete $players{$oldest_player->{name}};
        }
        unshift @players, {name => $name, ip => $ip};
        $players{$name} = 1;
    }
    close $fh;
    return \@players;
}

package main;

my $app = Mjollnir->new;
my $handler = sub { $app->run_psgi(@_) };

$handler;
