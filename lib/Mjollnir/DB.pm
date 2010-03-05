package Mjollnir::DB;
use strict;
use warnings;
use File::Spec;
use Cwd ();

use ORLite {
    file         => File::Spec->joinpath((File::Spec->splitpath(Cwd::realpath(__FILE__)))[0,1], 'mjollnir.db'),
    create       => sub {
        my $dbh = shift;
        $dbh->do($_) for split /;/, <<END_SQL;
CREATE TABLE players (
    steamid TEXT PRIMARY KEY,
);
CREATE TABLE id_bans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    steamid TEXT,
    timestamp INTEGER
);
CREATE TABLE ip_bans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ip TEXT,
    steamid TEXT,
    timestamp INTEGER
);
CREATE TABLE player_names (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    steamid TEXT,
    name TEXT,
    timestamp INTEGER
);
CREATE TABLE player_ips (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    steamid TEXT,
    ip TEXT,
    timestamp INTEGER
);
END_SQL
    },
    cleanup      => 'VACUUM',
);

1;
