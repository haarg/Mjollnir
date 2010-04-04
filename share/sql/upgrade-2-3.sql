DROP TABLE ip_bans;
CREATE TABLE ip_bans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ip TEXT,
    timestamp INTEGER
);
CREATE UNIQUE INDEX ip_bans_ip ON ip_bans (ip);

ALTER TABLE player_names ADD COLUMN stripped_name TEXT;
CREATE INDEX player_names_sid_stripped_name ON player_names (steam_id, stripped_name);
