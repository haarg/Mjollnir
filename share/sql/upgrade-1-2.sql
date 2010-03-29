DELETE FROM player_names WHERE steam_id IS NULL;
DELETE FROM player_ips WHERE steam_id IS NULL;
DELETE FROM id_bans WHERE steam_id IS NULL;
DELETE FROM player_names WHERE id NOT IN (SELECT MAX(id) FROM player_names GROUP BY steam_id, name);
DELETE FROM player_ips WHERE id NOT IN (SELECT MAX(id) FROM player_ips GROUP BY steam_id, ip);
DELETE FROM id_bans WHERE id NOT IN (SELECT MAX(id) FROM id_bans GROUP BY steam_id);

CREATE UNIQUE INDEX IF NOT EXISTS id_bans_sid ON id_bans (steam_id);
CREATE INDEX IF NOT EXISTS ip_bans_ip ON ip_bans (ip);
CREATE UNIQUE INDEX IF NOT EXISTS player_names_sid_name ON player_names (steam_id, name);
CREATE INDEX IF NOT EXISTS player_names_sid on player_names (steam_id ASC);
CREATE UNIQUE INDEX IF NOT EXISTS player_ips_sid_ip ON player_ips (steam_id, ip);
CREATE INDEX IF NOT EXISTS player_ips_sid on player_ips (steam_id ASC);
CREATE UNIQUE INDEX IF NOT EXISTS name_bans_name ON name_bans (name_pattern);

UPDATE id_bans
SET steam_id = substr(steam_id, 9, 8) || substr(steam_id, 1, 8)
WHERE steam_id IS NOT NULL;

UPDATE ip_bans
SET steam_id = substr(steam_id, 9, 8) || substr(steam_id, 1, 8)
WHERE steam_id IS NOT NULL;

UPDATE player_names
SET steam_id = substr(steam_id, 9, 8) || substr(steam_id, 1, 8)
WHERE steam_id IS NOT NULL;

UPDATE player_ips
SET steam_id = substr(steam_id, 9, 8) || substr(steam_id, 1, 8)
WHERE steam_id IS NOT NULL;

PRAGMA auto_vacuum = FULL;
VACUUM;
