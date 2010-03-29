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
