CREATE TABLE player (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    steam_id TEXT,
    banned  INTEGER,
    ban_reason INTEGER,
    ban_timestamp INTEGER,
    vac_banned INTEGER,
    web_timestamp INTEGER
);
CREATE UNIQUE INDEX player_sid ON player (steam_id);

INSERT INTO
    player (steam_id, banned, ban_reason, ban_timestamp, vac_banned, web_timestamp)
SELECT id_bans.steam_id, 1, reason, id_bans.timestamp, player_ids.vac_banned, player_ids.timestamp
FROM id_bans
LEFT JOIN player_ids
    ON id_bans.steam_id = player_ids.steam_id;

INSERT OR IGNORE INTO
    player (steam_id, vac_banned, web_timestamp)
SELECT steam_id, vac_banned, timestamp
FROM player_ids;

DROP TABLE player_ids;
DROP TABLE id_bans;
