package Mjollnir::DB;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.01;

use File::ShareDir ();
use File::Spec     ();
use DBI;

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    my $data_dir = File::ShareDir::dist_dir('Mjollnir');
    my $db_file  = File::Spec->catfile( $data_dir, 'mjollnir.db' );
    my $create   = !-e $db_file;
    $self->{dbh} = DBI->connect( 'dbi:SQLite:' . $db_file );
    if ($create) {
        $self->_create;
    }
    return $self;
}

sub _create {
    my $self = shift;
    my $dbh  = $self->{dbh};
    $dbh->do($_) for split /;/, <<END_SQL;
    CREATE TABLE id_bans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        steam_id TEXT,
        timestamp INTEGER
    );
    CREATE TABLE ip_bans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ip TEXT,
        steam_id TEXT,
        timestamp INTEGER
    );
    CREATE TABLE player_names (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        steam_id TEXT,
        name TEXT,
        timestamp INTEGER
    );
    CREATE TABLE player_ips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        steam_id TEXT,
        ip TEXT,
        timestamp INTEGER
    );
END_SQL
}

sub dbh {
    my $self = shift;
    return $self->{dbh};
}

sub get_names {
    my $self = shift;
    my $id   = shift;

    my $dbh = $self->dbh;
    my @names = map {@$_} @{
        $dbh->selectall_arrayref(
            'SELECT name FROM player_names WHERE steam_id = ? ORDER BY timestamp DESC',
            {}, $id,
        ) };
    return \@names;
}

sub add_name {
    my $self = shift;
    my $id   = shift;
    my $name = shift;

    my $dbh = $self->dbh;
    my $row
        = $dbh->selectrow_arrayref(
        'SELECT id FROM player_names WHERE steam_id = ? AND name = ?',
        {}, $id, $name, );
    if ($row) {
        $dbh->do(
            'UPDATE player_names SET steam_id = ?, name = ?, timestamp = ? WHERE id = ?',
            {}, $id, $name, time, $row->[0] );
    }
    else {
        $dbh->do(
            'INSERT INTO player_names (steam_id, name, timestamp) VALUES (?, ?, ?)',
            {}, $id, $name, time
        );
    }
}

sub get_ips {
    my $self = shift;
    my $id   = shift;

    my $dbh = $self->dbh;
    my @ips = map {@$_} @{
        $dbh->selectall_arrayref(
            'SELECT ip FROM player_ips WHERE steam_id = ? ORDER BY timestamp DESC',
            {}, $id,
        ) };
    return \@ips;
}

sub add_ip {
    my $self = shift;
    my $id   = shift;
    my $ip   = shift;

    my $dbh = $self->dbh;
    my $row
        = $dbh->selectrow_arrayref(
        'SELECT id FROM player_ips WHERE steam_id = ? AND ip = ?',
        {}, $id, $ip, );
    if ($row) {
        $dbh->do( 'UPDATE player_ips SET timestamp = ? WHERE id = ?',
            {}, time, $row->[0] );
    }
    else {
        $dbh->do(
            'INSERT INTO player_ips (steam_id, ip, timestamp) VALUES (?, ?, ?)',
            {}, $id, $ip, time
        );
    }
}

sub check_banned_id {
    my $self = shift;
    my $id   = shift;

    my $dbh = $self->dbh;
    my ($match) = @{
        $dbh->selectrow_arrayref(
            'SELECT COUNT(*) FROM id_bans WHERE steam_id = ?',
            {}, $id, ) };
    return $match;
}

sub check_banned_ip {
    my $self = shift;
    my $ip   = shift;

    my $dbh = $self->dbh;
    my ($match) = @{
        $dbh->selectrow_arrayref( 'SELECT COUNT(*) FROM ip_bans WHERE ip = ?',
            {}, $ip, ) };
    return $match;
}

sub get_ip_bans {
    my $self = shift;

    my $dbh = $self->dbh;
    my @ips = map {@$_} @{
        $dbh->selectall_arrayref('SELECT ip FROM ip_bans ORDER BY timestamp DESC')
    };
    return \@ips;
}

sub get_id_bans {
    my $self = shift;

    my $dbh = $self->dbh;
    my @ids = map {@$_} @{
        $dbh->selectall_arrayref('SELECT steam_id FROM id_bans ORDER BY timestamp DESC')
    };
    return \@ids;
}

sub add_ip_ban {
    my $self = shift;
    my $ip   = shift;
    my $id   = shift;
    my $dbh  = $self->dbh;

    my $row;
    if ($id) {
        $row
            = $dbh->selectrow_arrayref(
            'SELECT id FROM ip_bans WHERE ip = ? AND steam_id = ?',
            {}, $ip, $id, );
    }
    else {
        $row
            = $dbh->selectrow_arrayref(
            'SELECT id FROM ip_bans WHERE ip = ? AND steam_id IS NULL',
            {}, $ip, );
    }
    if ($row) {
        $dbh->do( 'UPDATE ip_bans SET timestamp = ? WHERE id = ?',
            {}, time, $row->[0] );
    }
    else {
        $dbh->do(
            'INSERT INTO ip_bans (steam_id, ip, timestamp) VALUES (?, ?, ?)',
            {}, $id, $ip, time
        );
    }
}

sub add_id_ban {
    my $self = shift;
    my $id   = shift;
    my $dbh  = $self->dbh;

    my $row
        = $dbh->selectrow_arrayref(
        'SELECT id FROM id_bans WHERE steam_id = ?',
        {}, $id, );
    if ($row) {
        $dbh->do( 'UPDATE id_bans SET timestamp = ? WHERE id = ?',
            {}, time, $row->[0] );
    }
    else {
        $dbh->do( 'INSERT INTO id_bans (steam_id, timestamp) VALUES (?, ?)',
            {}, $id, time );
    }
}

sub get_id_for_ip {
    my $self = shift;
    my $ip   = shift;
    my $dbh  = $self->dbh;

    my $row = $dbh->selectrow_arrayref(
        'SELECT steam_id FROM player_ips WHERE ip = ? ORDER BY timestamp DESC LIMIT 1',
        {}, $ip,
    );
    return $row->[0]
        if $row;
    return;
}

sub get_latest_players {
    my $self  = shift;
    my $limit = shift // 16;
    my $dbh   = $self->dbh;

    my $players = $dbh->selectall_arrayref( <<"END_SQL", { Slice => {} } );
SELECT player_names.steam_id, name, ip, player_names.timestamp FROM player_names INNER JOIN player_ips ON player_names.steam_id = player_ips.steam_id
WHERE player_names.timestamp = (SELECT MAX(timestamp) FROM player_names a WHERE a.steam_id = player_names.steam_id)
    AND player_ips.timestamp = (SELECT MAX(timestamp) FROM player_ips a WHERE a.steam_id = player_ips.steam_id)
ORDER BY player_names.timestamp DESC
LIMIT $limit;
END_SQL
    for my $player ( @{$players} ) {
        $player->{banned_id} = $self->check_banned_id( $player->{steam_id} );
        $player->{banned_ip} = $self->check_banned_ip( $player->{ip} );
    }
    return $players;
}

1;

__END__
'
join: ip id name
    check latest name for id
        add new name/id listing or
        update timestamp
    check latest ip for id
        add new name/id listing or
        update timestamp
    banned id?
        add ip+id ban

ident
    find id for ip
    check latest name for id
        add new name/id listing or
        update timestamp

-- web ---------
ban by id:
    add ban for ip address
    store id

ban by ip
    add ban for ip address

get player list
    get latest players by id
    check bans against ips
    check bans against ids

get player info
    get bans for id
    get names for id
    get ips for id

unban ip
    remove ip ban listing
    wipe bans
    add bans for ips

unban id
    remove id ban listing
    remove id associated ip ban listings
    wipe bans
    add bans for ips

'
