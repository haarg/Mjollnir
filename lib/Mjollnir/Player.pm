package Mjollnir::Player;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.01;

use Mjollnir::DB;
use Mjollnir::IPBan;
use LWP::UserAgent;
use XML::LibXML;
use Math::BigInt;
use AnyEvent::HTTP;

sub new {
    my $class = shift;
    my $db = shift;
    my $steam_id = lc shift;

    my $self = bless {}, $class;
    $self->{steam_id} = $steam_id;
    $self->{db} = $db;
    return $self;
}

sub _db_read {
    my $self = shift;
    my $db = $self->{db};
    @{$self}{qw(banned ban_reason ban_timestamp vac_banned web_timestamp)} = $db->selectrow_array(
        'SELECT banned, ban_reason, ban_timestamp, vac_banned, web_timestamp FROM player WHERE steam_id = ?',
        {}, $self->id);
    return 1;
}

sub _db_write {
    my $self = shift;
    my $db = $self->{db};
    $db->do('INSERT OR REPLACE INTO player (steam_id, banned, ban_reason, ban_timestamp, vac_banned, web_timestamp) VALUES (?,?,?,?,?,?)',
        {}, $self->id, @{$self}{qw(banned ban_reason ban_timestamp vac_banned web_timestamp)});
}

sub is_banned {
    my $self = shift;
    my $db = $self->{db};
    if (!exists $self->{banned}) {
        $self->_db_read;
    }
    return $self->{banned};
}

sub ban_reason {
    my $self = shift;
    my $db = $self->{db};
    if (!exists $self->{ban_reason}) {
        $self->_db_read;
    }
    return $self->{ban_reason};
}

sub is_kicked {
    my $self = shift;
    my $db = $self->{db};
    my $match = $db->selectrow_array( 'SELECT COUNT(*) FROM ip_bans WHERE ip = ?',  {}, $self->ip );
    return $match;
}

sub is_name_banned {
    my $self = shift;
    my $db = $self->{db};
    return $db->check_banned_name($self->name);
}

sub ban {
    my $self   = shift;
    my $reason = shift;
    my $db     = $self->{db};
    $self->_db_read;
    $self->{banned} = 1;
    $self->{ban_reason} = $reason;
    $self->{ban_timestamp} = time;
    $self->_db_write;
    $self->kick;
    return 1;
}

sub validate {
    my $self = shift;
    $self->refresh;
    if ( $self->is_banned || $self->is_name_banned ) {
        $self->kick;
    }
    elsif ( $self->vac_banned ) {
        $self->ban('VAC banned');
    }
    return;
}

sub unban {
    my $self = shift;
    my $db   = $self->{db};
    $self->_db_read;
    $self->{banned} = 0;
    $self->{ban_reason} = undef;
    $self->{ban_timestamp} = undef;
    $self->_db_write;
    $db->clear_ip_bans;
    Mjollnir::IPBan::clear_bans();
    return 1;
}

sub kick {
    my $self = shift;
    my $db  = $self->{db};

    $db->do(
        'INSERT OR REPLACE INTO ip_bans (ip, timestamp) VALUES (?, ?)',
        {}, $self->ip, time
    );
    return Mjollnir::IPBan::ban_ip($self->ip);
}

sub ips {
    my $self = shift;
    my $db = $self->{db};
    my @ips = map {@$_} @{
        $db->selectall_arrayref(
            'SELECT ip FROM player_ips WHERE steam_id = ? ORDER BY timestamp DESC',
            {}, $self->id,
        ) };
    return wantarray ? @ips : \@ips;
}

sub ip {
    my $self = shift;
    my $db = $self->{db};
    return $self->{ip}
        if $self->{ip};
    my $ip = $self->{ip} = $db->selectrow_array(
        'SELECT ip FROM player_ips WHERE steam_id = ? ORDER BY timestamp DESC LIMIT 1',
        {}, $self->id,
    );
    return $ip;
}

sub add_ip {
    my $self = shift;
    my $ip = shift;
    my $db = $self->{db};

    $self->{ip} //= $ip;

    $db->do(
        'INSERT OR REPLACE INTO player_ips (steam_id, ip, timestamp) VALUES (?, ?, ?)',
        {}, $self->id, $ip, time
    );
    return 1;
}

sub _load_name {
    my $self = shift;
    my $db = $self->{db};
    if (!defined $self->{name}) {
        $self->{name} = $db->selectrow_array(
            'SELECT name FROM player_names WHERE steam_id = ? ORDER BY timestamp DESC LIMIT 1',
            {}, $self->id
        );
    }
    if (!defined $self->{stripped_name}) {
        $self->{stripped_name} = $self->{name};
        $self->{stripped_name} =~ s/\^\d//g;
    }
    return 1;
}

sub name {
    my $self = shift;
    $self->_load_name;
    return $self->{name};
}

sub stripped_name {
    my $self = shift;
    $self->_load_name;
    return $self->{stripped_name};
}

sub add_name {
    my $self = shift;
    my $name = shift;
    my $db = $self->{db};

    if (!defined $self->{name}) {
        $self->{name} = $name;
        delete $self->{stripped_name};
    }

    my $stripped_name = $name;
    $stripped_name =~ s/\^\d//g;

    $db->do(
        'INSERT OR REPLACE INTO player_names (steam_id, name, stripped_name, timestamp) VALUES (?, ?, ?, ?)',
        {}, $self->id, $name, $stripped_name, time
    );
    return 1;
}

sub names {
    my $self = shift;
    my $db = $self->{db};
    my @names = map {@$_} @{
        $db->selectall_arrayref(
            'SELECT name FROM player_names WHERE steam_id = ? ORDER BY timestamp DESC',
            {}, $self->id,
        ) };
    return wantarray ? @names : \@names;
}

sub stripped_names {
    my $self = shift;
    my $db = $self->{db};
    my @stripped_names = map {@$_} @{
        $db->selectall_arrayref(
            'SELECT stripped_name FROM player_names WHERE steam_id = ? ORDER BY timestamp DESC',
            {}, $self->id,
        ) };
    return wantarray ? @stripped_names : \@stripped_names;
}

sub updated {
    my $self = shift;
    my $db = $self->{db};
    if (! exists $self->{web_timestamp}) {
        $self->_db_read;
    }
    if (@_) {
        $self->{web_timestamp} = shift;
        $self->_db_write;
    }
    return $self->{web_timestamp};
}

sub id {
    my $self = shift;
    return $self->{steam_id};
}

sub community_id {
    my $self = shift;
    my $id = $self->id;
    my $dec_id = Math::BigInt->from_hex('0x' . $id)->bstr;
    return $dec_id;
}

sub community_link {
    my $self = shift;
    my %opt = @_;
    my $link = 'http://steamcommunity.com/profiles/' . $self->community_id . '/';
    if ($opt{xml}) {
        $link .= '?xml=1';
    }
    return $link;
}

sub refresh {
    my $self = shift;
    my $updated = $self->updated;
    if (!$updated || $updated < time - 10 * 60 * 60) {
        $self->update_from_web;
    }
}

sub vac_banned {
    my $self = shift;
    my $db = $self->{db};
    $self->_db_read;
    if (@_) {
        $self->{vac_banned} = shift;
        $self->_db_write;
    }
    return $self->{vac_banned};
}

sub update_from_web {
    my $self = shift;

    my $xml_url = $self->community_link(xml => 1);
    my $data = $self->_xml_info($xml_url);
    if ($data->{player_name}) {
        $self->add_name( $data->{player_name} );
    }
    $self->vac_banned($data->{vac_banned});
    $self->updated(time);
    return 1;
}

sub new_by_link {
    my $class = shift;
    my $db = shift;
    my $link = shift;

    if ( $link =~ m{\Ahttp://(?:www\.)?steamcommunity\.com/profiles/(\d+)}msx ) {
        return $class->new_by_community_id($db, $1);
    }
    elsif ( $link =~ m{\Ahttp://(?:www\.)?steamcommunity\.com/id/([^/]+)}msx ) {
        my $xml_url = "http://steamcommunity.com/id/$1/?xml=1";
        my $data = $class->_xml_info($xml_url);
        return
            if !$data->{community_id};
        my $player = $class->new_by_community_id($db, $data->{community_id});
        if ($player && $data->{player_name}) {
            $player->add_name( $data->{player_name} );
        }
        $player->vac_banned($data->{vac_banned});
        $player->updated(time);
        return $player;
    }
    return;
}

sub new_by_link_cb {
    my $class = shift;
    my $db = shift;
    my $link = shift;
    my $cb = shift;

    if ( $link =~ m{\Ahttp://(?:www\.)?steamcommunity\.com/profiles/(\d+)}msx ) {
        $cb->($class->new_by_community_id($db, $1));
        return;
    }
    elsif ( $link =~ m{\Ahttp://(?:www\.)?steamcommunity\.com/id/([^/]+)}msx ) {
        my $xml_url = "http://steamcommunity.com/id/$1/?xml=1";
        http_get $xml_url, sub {
            my ($body, $hdr) = @_;
            my $data = $class->_xml_parse($body);
            return
                if !$data->{community_id};
            my $player = $class->new_by_community_id($db, $data->{community_id});
            if ($player && $data->{player_name}) {
                $player->add_name( $data->{player_name} );
            }
            $player->vac_banned($data->{vac_banned});
            $player->updated(time);
            $cb->($player);
        };
    }
    return;
}


sub _xml_info {
    my $class = shift;
    my $url = shift;
    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);
    my $response = $ua->get($url);
    return $class->_xml_parse($response->content);
}

sub _xml_parse {
    my $class = shift;
    my $data = shift;
    my $xml = XML::LibXML->load_xml(string => $data);
    my $get_tag = sub {
        my $element = $xml->getElementsByTagName(shift);
        return undef
            unless $element;
        $element = $element->[0];
        return undef
            unless $element;
        $element = $element->textContent;
        return $element;
    };
    return {
        player_name => $get_tag->('steamID'),
        community_id => $get_tag->('steamID64'),
        vac_banned => $get_tag->('vacBanned') ? 1 : 0,
    };
}

sub new_by_community_id {
    my $class = shift;
    my $db = shift;
    my $community_id = shift;
    my $hex_id = lc Math::BigInt->new($community_id)->as_hex;
    $hex_id =~ s/^0x//;
    $hex_id = ('0' x (16 - length $hex_id)) . $hex_id;
    return $class->new($db, $hex_id);
}

sub new_by_ip {
    my $class   = shift;
    my $db      = shift;
    my $ip      = shift;

    my $row = $db->selectrow_arrayref(
        'SELECT steam_id FROM player_ips WHERE ip = ? ORDER BY timestamp DESC LIMIT 1',
        {}, $ip,
    );
    return $class->new($db, $row->[0])
        if $row;
    return;
}

sub find_by_ip {
    my $class   = shift;
    my $db      = shift;
    my $ip      = shift;

    my $players = $db->selectall_arrayref(
        'SELECT steam_id, ip FROM player_ips WHERE ip = ? ORDER BY timestamp DESC',
        { Slice => {} },
        $ip,
    );
    for my $player ( @{ $players } ) {
        $player->{db} = $db;
        bless $player, $class;
    }
    return wantarray ? @$players : $players;
}

sub find_by_name {
    my $class   = shift;
    my $db      = shift;
    my $name    = shift;

    $name = '%' . $name . '%';
    my $players = $db->selectall_arrayref(
        'SELECT steam_id, name FROM player_names WHERE stripped_name LIKE ? ORDER BY timestamp DESC',
        { Slice => {} },
        $name,
    );
    for my $player ( @{ $players } ) {
        $player->{db} = $db;
        bless $player, $class;
    }
    return wantarray ? @$players : $players;
}

sub find_latest {
    my $class = shift;
    my $db    = shift;
    my $limit = shift // 18;

    my $players = $db->selectall_arrayref( <<"END_SQL", { Slice => {} } );
    SELECT
        steam_id,
        ip
    FROM
        player_ips INNER JOIN (
            SELECT
                MAX(id) AS id
            FROM
                player_ips
            GROUP BY
                steam_id
            ORDER BY
                MAX(timestamp) DESC, MAX(id) DESC
            LIMIT $limit
        ) ids ON player_ips.id = ids.id
END_SQL
    my @steam_ids = map { $_->{steam_id} } @$players;

    my $names = $db->selectall_hashref( <<"END_SQL", 'steam_id', {}, @steam_ids );
        SELECT
            steam_id,
            name,
            stripped_name
        FROM
            player_names INNER JOIN (
                SELECT
                    MAX(id) AS id
                FROM
                    player_names
                WHERE
                    steam_id IN (@{[join ',', ('?') x @steam_ids]})
                GROUP BY
                    steam_id
                ORDER BY
                    MAX(timestamp) DESC, MAX(id) DESC
                LIMIT $limit
            ) ids ON player_names.id = ids.id
END_SQL

    for my $player ( @{$players} ) {
        $player->{name} = $names->{$player->{steam_id}}->{name};
        $player->{stripped_name} = $names->{$player->{steam_id}}->{stripped_name};
        $player->{db} = $db;
        bless $player, $class;
    }
    return wantarray ? @$players : $players;
}

sub find_banned {
    my $class = shift;
    my $db   = shift;
    
    my $players = $db->selectall_arrayref('SELECT steam_id FROM player WHERE banned ORDER BY ban_timestamp DESC', { Slice => {} });
    for my $player ( @{ $players } ) {
        $player->{db} = $db;
        bless $player, $class;
    }
    return wantarray ? @$players : $players;
}

1;

__END__

=head1 NAME

Mjollnir::Player - Player object for Mjollnir

=head1 AUTHOR

Graham Knop <haarg@haarg.org>

=head1 LICENSE

Copyright (c) 2010, Graham Knop

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0. For more details, see the
full text of the licenses in the directory LICENSES.

=cut
