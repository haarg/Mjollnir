package Mjollnir::DB;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.03;

use File::ShareDir ();
use File::Spec     ();
use DBI;
use DBD::SQLite;
use constant DB_SCHEMA_VERSION => 2;

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    $self->{dbh} = $self->_init_dbh;
    return $self;
}

sub db_filename {
    my $data_dir = File::ShareDir::dist_dir('Mjollnir');
    my $db_file  = File::Spec->catfile( $data_dir, 'mjollnir.db' );
    return $db_file;
}

sub _init_dbh {
    my $self = shift;
    my $db_file = $self->db_filename;
    my $create = !-e $db_file;
    my $dbh = DBI->connect( 'dbi:SQLite:' . $db_file );
    if ($create) {
        $self->_create($dbh);
        $dbh->do('PRAGMA user_version = ' . DB_SCHEMA_VERSION);
    }
    else {
        my $current_db_version = $dbh->selectrow_array('PRAGMA user_version');
        $current_db_version ||= 0;
        if ($current_db_version == DB_SCHEMA_VERSION) {
            return $dbh;
        }
        elsif ($current_db_version < DB_SCHEMA_VERSION) {
            for my $step ($current_db_version .. DB_SCHEMA_VERSION - 1) {
                my $filename = File::ShareDir::dist_file('Mjollnir', 'sql/upgrade-' . $step . '-' . ($step + 1) . '.sql');
                $self->_run_sql_script($dbh, $filename);
                $dbh->do('PRAGMA user_version = ' . ($step + 1));
            }
        }
        else {
            die;
        }
    }

    return $dbh;
}

sub _run_sql_script {
    my $self = shift;
    my $dbh = shift;
    my $filename = shift;
    open my $fh, '<', $filename
        or die "Can't open $filename: $!";
    my $sql = do { local $/; <$fh> };
    close $fh;
    my @sql = grep { /\S/ } split /;$/msx, $sql;
    for my $stmt (@sql) {
        $dbh->do($stmt);
    }
    return 1;
}

sub _create {
    my $self = shift;
    my $dbh  = shift;
    my $filename = File::ShareDir::dist_file('Mjollnir', 'sql/create.sql');
    return $self->_run_sql_script($filename);
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
    $dbh->do(
        'INSERT OR REPLACE INTO player_names (steam_id, name, timestamp) VALUES (?, ?, ?)',
        {}, $id, $name, time
    );
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
    $dbh->do(
        'INSERT OR REPLACE INTO player_ips (steam_id, ip, timestamp) VALUES (?, ?, ?)',
        {}, $id, $ip, time
    );
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

    $dbh->do( 'INSERT OR REPLACE INTO id_bans (steam_id, timestamp) VALUES (?, ?)',
        {}, $id, time );
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

    my $names = $dbh->selectall_arrayref( <<"END_SQL", { Slice => {} } );
    SELECT
        steam_id,
        name
    FROM
        player_names INNER JOIN (
            SELECT
                MAX(id) AS id
            FROM
                player_names
            GROUP BY
                steam_id
            ORDER BY
                MAX(timestamp) DESC, MAX(id) DESC
            LIMIT $limit
        ) ids ON player_names.id = ids.id
END_SQL
    my @steam_ids = map { $_->{steam_id} } @$names;

    my $ips = $dbh->selectall_hashref( <<"END_SQL", 'steam_id', {}, @steam_ids );
        SELECT
            steam_id,
            ip
        FROM
            player_ips INNER JOIN (
                SELECT
                    MAX(id) AS id
                FROM
                    player_ips
                WHERE
                    steam_id IN (@{[join ',', ('?') x @steam_ids]})
                GROUP BY
                    steam_id
                ORDER BY
                    MAX(timestamp) DESC, MAX(id) DESC
                LIMIT $limit
            ) ids ON player_ips.id = ids.id
END_SQL

    for my $player ( @{$names} ) {
        $player->{ip} = $ips->{$player->{steam_id}}->{ip};
        $player->{banned_id} = $self->check_banned_id( $player->{steam_id} );
        $player->{banned_ip} = $self->check_banned_ip( $player->{ip} );
    }
    return $names;
}

1;

__END__

=head1 NAME

Mjollnir::DB - Database storage for Mjollnir

=head1 AUTHOR

Graham Knop <haarg@haarg.org>

=head1 LICENSE

Copyright (c) 2010, Graham Knop
 
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0. For more details, see the
full text of the licenses in the directory LICENSES.

=cut
