PRAGMA auto_vacuum = FULL;

CREATE TABLE id_bans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    steam_id TEXT,
    timestamp INTEGER
);
CREATE UNIQUE INDEX id_bans_sid ON id_bans (steam_id);

CREATE TABLE ip_bans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ip TEXT,
    steam_id TEXT,
    timestamp INTEGER
);
CREATE INDEX ip_bans_ip ON ip_bans (ip);

CREATE TABLE player_names (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    steam_id TEXT,
    name TEXT,
    timestamp INTEGER
);
CREATE UNIQUE INDEX player_names_sid_name ON player_names (steam_id, name);
CREATE INDEX player_names_sid on player_names (steam_id ASC);

CREATE TABLE player_ips (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    steam_id TEXT,
    ip TEXT,
    timestamp INTEGER
);
CREATE UNIQUE INDEX player_ips_sid_ip ON player_ips (steam_id, ip);
CREATE INDEX player_ips_sid on player_ips (steam_id ASC);

CREATE TABLE name_bans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name_pattern TEXT,
    timestamp INTEGER
);
CREATE UNIQUE INDEX name_bans_name ON name_bans (name_pattern);
