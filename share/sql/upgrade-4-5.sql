CREATE TABLE player_ids (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    steam_id TEXT,
    vac_banned INTEGER,
    timestamp INTEGER
);
CREATE UNIQUE INDEX player_ids_id ON player_ids (steam_id);
