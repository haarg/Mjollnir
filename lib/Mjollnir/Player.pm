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

sub new {
    my $class = shift;
    my $db = shift;
    my $steam_id = lc shift;
    
    my $self = bless {}, $class;
    $self->{steam_id} = $steam_id;
    $self->{db} = $db;
    return $self;
}

sub is_banned {
    my $self = shift;
    my $db = $self->{db};
    my $match =
        $db->selectrow_array(
            'SELECT COUNT(*) FROM id_bans WHERE steam_id = ?',
            {}, $self->id );
    return $match;
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
    my $self = shift;
    my $db   = $self->{db};

    $db->do( 'INSERT OR REPLACE INTO id_bans (steam_id, timestamp) VALUES (?, ?)',
        {}, $self->id, time );
    return 1;
}

sub unban {
    my $self = shift;
    my $db   = $self->{db};

    $db->do( 'DELETE FROM id_bans WHERE steam_id = ?', {}, $self->id);
    $db->do( 'DELETE FROM ip_bans WHERE ip = ?', {}, $self->ip);
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

sub name {
    my $self = shift;
    $self->_load_name;
    return $self->{name};
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
    $self->updated(time);
    return 1;
}

sub updated {
    my $self = shift;
    my $when = shift;
    my $db = $self->{db};
    if ($when) {
        $self->{updated} = $when;
        $db->do(
            'INSERT OR REPLACE INTO player_ids (steam_id, timestamp) VALUES (?, ?)',
            {}, $self->id, $when
        );
    }
    elsif ($self->{updated}) {
        return $self->{updated};
    }
    else {
        return $self->{updated} = $db->selectrow_array(
            'SELECT timestamp FROM player_ids WHERE steam_id = ?',
            {}, $self->id
        );
    }
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

sub stripped_name {
    my $self = shift;
    $self->_load_name;
    return $self->{stripped_name};
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
    if (@_) {
        $self->{vac_banned} = shift;
        $db->do(
            'UPDATE player_ids SET vac_banned = ? WHERE steam_id = ?',
            {}, $self->{vac_banned}, $self->id
        );
    }
    if (exists $self->{vac_banned}) {
        return $self->{vac_banned};
    }
    else {
        return $self->{vac_banned} = $db->selectrow_array(
            'SELECT vac_banned FROM player_ids WHERE steam_id = ?',
            {}, $self->id
        );
    }
}

sub update_from_web {
    my $self = shift;

    my $xml_url = $self->community_link(xml => 1);
    my $data = $self->_xml_info($xml_url);
    if ($data->{player_name}) {
        $self->add_name( $data->{player_name} );
    }
    if ($data->{vac_banned}) {
        $self->vac_banned(1);
    }
    return 1;
}

sub new_by_link {
    my $class = shift;
    my $db = shift;
    my $link = shift;

    if ( $link =~ m{\Ahttp://steamcommunity.com/profiles/(\d+)/}msx ) {
        return $class->new_by_community_id($db, $1);
    }
    elsif ( $link =~ m{\Ahttp://steamcommunity.com/id/([^/]+)/}msx ) {
        my $xml_url = "http://steamcommunity.com/id/$1/?xml=1";
        my $data = $class->_xml_info($xml_url);
        my $player = $class->new_by_community_id($db, $data->{community_id});
        if ($player && $data->{player_name}) {
            $player->add_name( $data->{player_name} );
        }
        if ($data->{vac_banned}) {
            $player->vac_banned(1);
        }
        return $player;
    }
    return;
}

sub _xml_info {
    my $class = shift;
    my $url = shift;
    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);
    my $response = $ua->get($url);
    my $xml = XML::LibXML->load_xml(string => $response->content);
    return {
        player_name => $xml->getElementsByTagName('steamID')->[0]->textContent,
        community_id => $xml->getElementsByTagName('steamID64')->[0]->textContent,
        vac_banned => $xml->getElementsByTagName('vacBanned')->[0]->textContent,
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
    
    my $players = $db->selectall_arrayref('SELECT steam_id FROM id_bans ORDER BY timestamp DESC', { Slice => {} });
    for my $player ( @{ $players } ) {
        $player->{db} = $db;
        bless $player, $class;
    }
    return wantarray ? @$players : $players;
}

1;
