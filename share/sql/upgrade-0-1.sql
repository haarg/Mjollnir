CREATE TABLE name_bans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name_pattern TEXT,
    timestamp INTEGER
);
CREATE UNIQUE INDEX name_bans_name ON name_bans (name_pattern);
