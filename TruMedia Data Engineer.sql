/* 1. The top 20 players ranked by slugging percentage in away games only in the 2023 season,
      limited to players with at least 250 total plate appearances. */

WITH away_player_games AS (
    SELECT  
      pg.*
    , g.date
    , ROW_NUMBER() OVER(PARTITION BY pg.player_id ORDER BY g.date DESC) AS r_desc
    FROM mlb_data.player_games pg
    INNER JOIN mlb_data.games g 
        ON 1=1
           AND pg.game_pk = g.game_pk 
           AND pg.team_id = g.away_team_id 
           AND g.season = 2023
)

-- SELECT * FROM away_player_games

, player_team_eos AS (
    SELECT 
      player_id 
    , team_id 
    FROM away_player_games
    WHERE 1=1
          AND r_desc = 1
)

-- SELECT * FROM player_team_eos

, away_player_stats AS (
    SELECT 
      player_id 
    , SUM(PA) AS total_pa
    , SUM(S + (2 * D) + (3 * T) + (4 * HR)) / (SUM(AB)) AS slg
    FROM away_player_games
    GROUP BY 1
    HAVING SUM(PA) >= 250
)

-- SELECT * FROM away_player_stats

, top_20_players AS (
    SELECT 
      *
    FROM away_player_stats 
    ORDER BY slg DESC 
    LIMIT 20
)

-- SELECT * FROM top_20_players

, final_data AS (
    SELECT 
      a.player_id 
    , p.name 
    , t.abbrev
    , t.name AS team_name 
    , a.total_pa 
    , a.slg
    FROM top_20_players a
    LEFT JOIN mlb_data.players p
        ON a.player_id = p.id 
    LEFT JOIN player_team_eos t_eos 
        ON a.player_id = t_eos.player_id 
    LEFT JOIN mlb_data.teams t 
        ON t_eos.team_id = t.id
)

SELECT * FROM final_data

;


/* 2. The top 20 players ranked by home runs in a single season between 2022 and 2023. */

WITH player_team_games AS (
    SELECT 
      pg.player_id 
    , pg.team_id
    , pg.HR 
    , g.season 
    , g.date 
    , ROW_NUMBER() OVER(PARTITION BY pg.player_id, g.season ORDER BY g.date DESC) AS r_desc
    FROM mlb_data.player_games pg
    INNER JOIN mlb_data.games g
      ON pg.game_pk = g.game_pk AND g.season BETWEEN 2022 AND 2023
) 

, player_team_eos AS (
    SELECT 
      player_id 
    , season
    , team_id 
    FROM player_team_games
    WHERE 1=1
          AND r_desc = 1
)

, total_hr_season AS (
    SELECT 
      pg.season
    , pg.player_id 
    , p.name
    , t.abbrev 
    , t.name AS team_name
    , SUM(pg.HR) AS total_HR
    FROM player_team_games pg
    LEFT JOIN mlb_data.players p 
        ON pg.player_id = p.id
    LEFT JOIN player_team_eos t_eos 
        ON pg.season = t_eos.season AND pg.player_id = t_eos.player_id
    LEFT JOIN mlb_data.teams t 
        ON t_eos.team_id = t.id
    GROUP BY 1,2,3,4,5
)

/* Using name to 'break ties', as criteria wasn't specified */
SELECT * FROM total_hr_season ORDER BY total_HR DESC, name LIMIT 20
;


/* 3. The top 20 teams ranked by total runs scored in a game between 2022 and 2023. */

WITH team_stats AS (
    SELECT 
      tg.game_pk
    , g.season 
    , g.date
    , tg.team_id 
    , SUM(tg.R) AS total_r
    FROM mlb_data.team_games tg
    INNER JOIN mlb_data.games g 
        ON tg.game_pk = g.game_pk AND g.season BETWEEN 2022 AND 2023
    GROUP BY 1,2,3,4
)

-- SELECT * FROM team_stats

SELECT 
  game_pk 
, season 
, t.abbrev 
, t.name AS team_name 
, total_r 
FROM team_stats ts 
LEFT JOIN mlb_data.teams t 
    ON ts.team_id = t.id
ORDER BY total_r DESC
LIMIT 20

;


/* 4. The top 20 non-Red Sox players ranked by total doubles at Fenway Park (venue ID 3)
over the 2022 and 2023 seasons combined. */

WITH player_team_games AS (
    SELECT 
      pg.player_id 
    , pg.team_id
    , t.abbrev 
    , t.name AS team_name
    , pg.D 
    , g.season 
    , g.date 
    , g.venue_id
    , ROW_NUMBER() OVER(PARTITION BY pg.player_id ORDER BY g.date DESC) AS r_desc
    FROM mlb_data.player_games pg
    INNER JOIN mlb_data.games g
      ON pg.game_pk = g.game_pk AND g.season BETWEEN 2022 AND 2023
    INNER JOIN mlb_data.teams t 
        ON pg.team_id = t.id
) 

, player_team_eos AS (
    SELECT 
      player_id 
    , season
    , abbrev
    , team_name 
    FROM player_team_games
    WHERE 1=1
          AND r_desc = 1
)

, fenway_stats AS (
    SELECT 
      ptg.player_id 
    , p.name
    , t_eos.abbrev 
    , t_eos.team_name
    , SUM(D) AS total_d
    FROM player_team_games ptg 
    LEFT JOIN player_team_eos t_eos 
        ON ptg.player_id = t_eos.player_id 
    LEFT JOIN mlb_data.players p 
        ON ptg.player_id = p.id 
    WHERE 1=1
          AND ptg.venue_id = 3
          AND ptg.abbrev <> 'BOS'
    GROUP BY 1,2
)

/* Using name to 'break ties', as criteria wasn't specified */
SELECT * FROM fenway_stats ORDER BY total_d DESC, name LIMIT 20

/* 5. Team standings organized by division, similar to what you would see on MLB.com
(https://www.mlb.com/standings/). */
WITH season_win_totals AS (
    SELECT 
      g.season 
    , tg.team_id 
    , COUNT(tg.game_pk) AS G
    , SUM(tg.win) AS W
    , SUM(tg.R) AS RS
    , SUM(tg.RA) AS RA
    , SUM(tg.home) AS G_HOME
    , SUM(CASE WHEN tg.home = 1 THEN tg.win END) AS W_HOME
    , COUNT(CASE WHEN tg.home = 0 THEN tg.game_pk END) AS G_AWAY
    , SUM(CASE WHEN tg.home = 0 THEN tg.win END) AS W_AWAY
    FROM mlb_data.team_games tg
    INNER JOIN mlb_data.games g
        ON tg.game_pk = g.game_pk AND g.season = 2023
    GROUP BY 1,2
)

-- SELECT * FROM season_win_totals

, standings_prep AS (
    SELECT 
      season 
    , t.league 
    , t.division
    , CASE
        WHEN t.division = 'E' THEN 1 
        WHEN t.division = 'C' THEN 2
        WHEN t.division = 'W' THEN 3 
        ELSE NULL 
      END AS division_order
    , t.abbrev 
    , t.name AS team_name 
    , W
    , (G - W) AS L
    , W / G AS PCT
    , RS
    , RA 
    , RS - RA AS DIFF 
    , G_HOME 
    , W_HOME 
    , G_HOME - W_HOME AS L_HOME
    , G_AWAY 
    , W_AWAY
    , G_AWAY - W_AWAY AS L_AWAY
    , ROW_NUMBER() OVER(PARTITION BY season, t.league, t.division ORDER BY W DESC) AS standings_r
    FROM season_win_totals swt
    LEFT JOIN mlb_data.teams t 
        ON swt.team_id = t.id

)

SELECT 
  season 
, league 
, division 
, abbrev
, team_name 
, W 
, L
, PCT 
, RS 
, RA 
, DIFF 
, CONCAT(W_HOME, '-', L_HOME) AS HOME
, CONCAT(W_AWAY, '-', L_AWAY) AS AWAY
FROM standings_prep
ORDER BY league, division_order, W DESC





-- WITH season_win_totals_prep AS (
--     SELECT 
--       g.season 
--     , g.date
--     , g.game_pk
--     , tg.team_id 
--     , tg.win AS game_win
--     , COUNT(tg.game_pk) OVER(PARTITION BY g.season, tg.team_id ORDER BY date) AS G
--     , SUM(tg.win) OVER(PARTITION BY g.season, tg.team_id ORDER BY date) AS W
--     , SUM(tg.R) OVER(PARTITION BY g.season, tg.team_id ORDER BY date) AS RS
--     , SUM(tg.RA) OVER(PARTITION BY g.season, tg.team_id ORDER BY date) AS RA
--     , SUM(tg.home) OVER(PARTITION BY g.season, tg.team_id ORDER BY date) AS G_HOME
--     , SUM(CASE WHEN tg.home = 1 THEN tg.win END) OVER(PARTITION BY g.season, tg.team_id ORDER BY date) AS W_HOME
--     , COUNT(CASE WHEN tg.home = 0 THEN tg.game_pk END) OVER(PARTITION BY g.season, tg.team_id ORDER BY date) AS G_AWAY
--     , SUM(CASE WHEN tg.home = 0 THEN tg.win END) OVER(PARTITION BY g.season, tg.team_id ORDER BY date) AS W_AWAY
--     FROM mlb_data.team_games tg
--     INNER JOIN mlb_data.games g
--         ON tg.game_pk = g.game_pk AND g.season = 2023
--     -- GROUP BY 1,2
-- )

-- -- SELECT * FROM season_win_totals_prep

-- , game_records_prep AS (
--     SELECT 
--       game_pk 
--     , date
--     , team_id 
--     , W
--     , (G - W) AS L 
--     , CASE WHEN W > (G - W) THEN 1 ELSE 0 END AS above_500
--     FROM season_win_totals_prep
-- )

-- , game_records_before AS (
--     SELECT 
--       game_pk 
--     , team_id
--     , LAG(W) OVER(PARTITION BY team_id ORDER BY game_pk, date ASC) AS W
--     , LAG(L) OVER(PARTITION BY team_id ORDER BY game_pk, date ASC) AS L 
--     , LAG(above_500) OVER(PARTITION BY team_id ORDER BY game_pk, date ASC) above_500
--     FROM game_records_prep
-- )

-- -- SELECT * FROM game_records

-- , season_win_totals AS (
--     SELECT 
--       a.* 
--     , COUNT(CASE WHEN b.above_500 = 1 THEN a.game_pk END) OVER(PARTITION BY a.season, a.team_id ORDER BY a.date) AS G_OPP_ABOVE_500
--     , SUM(CASE WHEN b.above_500 = 1 THEN a.game_win END) OVER(PARTITION BY a.season, a.team_id ORDER BY a.date) AS W_OPP_ABOVE_500
--     , b.team_id AS opp_team
--     , b.above_500 AS opp_team_above_500
--     FROM season_win_totals_prep a 
--     LEFT JOIN game_records_before b
--         ON a.game_pk = b.game_pk AND a.team_id <> b.team_id
-- )

-- -- SELECT * FROM season_win_totals

-- , standings_prep AS (
--     SELECT 
--       season 
--     , date
--     , t.league 
--     , t.division
--     , CASE
--         WHEN t.division = 'E' THEN 1 
--         WHEN t.division = 'C' THEN 2
--         WHEN t.division = 'W' THEN 3 
--         ELSE NULL 
--       END AS division_order
--     , t.abbrev 
--     , t.name AS team_name 
--     , W
--     , (G - W) AS L
--     , W / G AS PCT
--     , RS
--     , RA 
--     , RS - RA AS DIFF 

--     , G_HOME 
--     , W_HOME 
--     , G_HOME - W_HOME AS L_HOME

--     , G_AWAY 
--     , W_AWAY
--     , G_AWAY - W_AWAY AS L_AWAY

--     , G_OPP_ABOVE_500
--     , W_OPP_ABOVE_500
--     , (G_OPP_ABOVE_500 - W_OPP_ABOVE_500) AS L_OPP_ABOVE_500

--     , G - G_OPP_ABOVE_500 AS G_OPP_BELOW_500
--     , W - W_OPP_ABOVE_500 AS W_OPP_BELOW_500
--     , (G - G_OPP_ABOVE_500) - (W - W_OPP_ABOVE_500) AS L_OPP_BELOW_500
--     , ROW_NUMBER() OVER(PARTITION BY season, t.league, t.division ORDER BY W DESC) AS standings_r
--     FROM season_win_totals swt
--     LEFT JOIN mlb_data.teams t 
--         ON swt.team_id = t.id

-- )

-- SELECT 
--   season 
-- , date
-- , league 
-- , division 
-- , abbrev
-- , team_name 
-- , W 
-- , L
-- , PCT 
-- , RS 
-- , RA 
-- , DIFF 
-- , CONCAT(W_HOME, '-', L_HOME) AS HOME
-- , CONCAT(W_AWAY, '-', L_AWAY) AS AWAY
-- , CONCAT(W_OPP_ABOVE_500, '-', L_OPP_ABOVE_500) AS ABOVE_500
-- -- , CONCAT(W_OPP_BELOW_500, '-', L_OPP_BELOW_500) AS BELOW_500
-- FROM standings_prep
-- WHERE 1=1
--       AND date = '2023-10-01'
-- ORDER BY date, league, division_order, W DESC







/* 6. Show off your creativity and SQL expertise by writing one or more additional queries that
combine the data in these tables. */