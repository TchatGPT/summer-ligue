-- ============================================================================
-- Bilan d'avancement de la Summer Ligue — aide à la décision « prolonger de 15 jours ? »
-- ============================================================================
-- Fin prévue : 30 septembre. Prolongation envisagée : jusqu'au 15 octobre.
-- Toutes les requêtes sont en LECTURE SEULE. À coller dans l'éditeur SQL Supabase,
-- une requête à la fois (chaque bloc est indépendant).
--
-- Définitions (alignées sur le code de l'appli) :
--   • limite de base    = flag app_flags.maxGames (60)
--   • limite perso      = min(65, base + players.extra_games)   -> cf. limiteJoueur()
--   • games jouées      = nombre de lignes dans games pour le joueur
--   • games restantes   = limite perso - games jouées (jamais négatif)
--   • « a fini »        = jouées >= 60                           -> cf. quotaGamesEpuise()
--   • « quasiment fini »= jouées >= 58 (60 - 2)                  -> cf. seuilFinLigue()
--   • « encore beaucoup » = au moins 15 games restantes (≈ 1 game/jour sur 15 jours de
--     prolongation). Ce seuil est un paramètre : change SEUIL_BEAUCOUP ci-dessous.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- REQUÊTE 1 — VUE D'ENSEMBLE : nb joueurs, games jouées / restantes, les 2 pourcentages
-- ---------------------------------------------------------------------------
WITH params AS (
  SELECT
    COALESCE((SELECT value::int FROM app_flags WHERE key = 'maxGames'), 60) AS base,
    2   AS marge_fin,        -- « quasiment fini » = base - marge_fin
    15  AS seuil_beaucoup    -- « encore beaucoup » = au moins N games restantes
),
par_joueur AS (
  SELECT
    p.id,
    p.name,
    LEAST(65, pr.base + COALESCE(p.extra_games, 0))                          AS limite,
    COUNT(g.id)                                                              AS jouees,
    GREATEST(0, LEAST(65, pr.base + COALESCE(p.extra_games, 0)) - COUNT(g.id)) AS restantes,
    pr.base, pr.marge_fin, pr.seuil_beaucoup
  FROM players p
  CROSS JOIN params pr
  LEFT JOIN games g ON g.player_id = p.id
  GROUP BY p.id, p.name, p.extra_games, pr.base, pr.marge_fin, pr.seuil_beaucoup
)
SELECT
  COUNT(*)                                                                   AS nb_joueurs,
  SUM(jouees)                                                                AS games_jouees_total,
  SUM(restantes)                                                             AS games_restantes_total,
  ROUND(AVG(jouees), 1)                                                      AS moyenne_jouees,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY jouees)                        AS mediane_jouees,
  ROUND(AVG(restantes), 1)                                                   AS moyenne_restantes,
  COUNT(*) FILTER (WHERE jouees >= base)                                     AS nb_ont_fini,
  ROUND(100.0 * COUNT(*) FILTER (WHERE jouees >= base) / COUNT(*), 1)        AS pct_ont_fini,
  COUNT(*) FILTER (WHERE jouees >= base - marge_fin)                         AS nb_quasi_fini,
  ROUND(100.0 * COUNT(*) FILTER (WHERE jouees >= base - marge_fin) / COUNT(*), 1) AS pct_quasi_fini,
  COUNT(*) FILTER (WHERE restantes >= seuil_beaucoup)                        AS nb_encore_beaucoup,
  ROUND(100.0 * COUNT(*) FILTER (WHERE restantes >= seuil_beaucoup) / COUNT(*), 1) AS pct_encore_beaucoup,
  COUNT(*) FILTER (WHERE jouees = 0)                                         AS nb_zero_game
FROM par_joueur;


-- ---------------------------------------------------------------------------
-- REQUÊTE 2 — RÉPARTITION PAR TRANCHE : combien de joueurs dans chaque situation
-- ---------------------------------------------------------------------------
WITH params AS (
  SELECT COALESCE((SELECT value::int FROM app_flags WHERE key = 'maxGames'), 60) AS base
),
par_joueur AS (
  SELECT
    p.id,
    COUNT(g.id) AS jouees,
    GREATEST(0, LEAST(65, pr.base + COALESCE(p.extra_games, 0)) - COUNT(g.id)) AS restantes,
    pr.base
  FROM players p
  CROSS JOIN params pr
  LEFT JOIN games g ON g.player_id = p.id
  GROUP BY p.id, p.extra_games, pr.base
),
tranches AS (
  SELECT
    CASE
      WHEN jouees >= base            THEN '1. Fini (60+)'
      WHEN jouees >= base - 2        THEN '2. Quasiment fini (58-59)'
      WHEN restantes <= 14           THEN '3. Bien avancé (3 à 14 restantes)'
      WHEN restantes <= 29           THEN '4. Encore beaucoup (15 à 29 restantes)'
      WHEN jouees = 0                THEN '6. Aucune game'
      ELSE                                '5. Très loin (30+ restantes)'
    END AS tranche,
    jouees, restantes
  FROM par_joueur
)
SELECT
  tranche,
  COUNT(*)                                            AS nb_joueurs,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_joueurs,
  SUM(restantes)                                      AS games_restantes_cumulees,
  ROUND(AVG(jouees), 1)                               AS moyenne_jouees
FROM tranches
GROUP BY tranche
ORDER BY tranche;


-- ---------------------------------------------------------------------------
-- REQUÊTE 3 — DÉTAIL PAR JOUEUR : jouées, restantes, statut, rythme, projection
-- ---------------------------------------------------------------------------
-- rythme_14j = games saisies sur les 14 derniers jours (d'après games.created_at).
-- projection_30_09 / projection_15_10 = games qu'il aurait joué à ce rythme,
-- plafonnées à sa limite. Un joueur est « finit_au_30_09 » si sa projection atteint 60.
WITH params AS (
  SELECT
    COALESCE((SELECT value::int FROM app_flags WHERE key = 'maxGames'), 60) AS base,
    DATE '2026-09-30' AS fin_prevue,
    DATE '2026-10-15' AS fin_prolongee
),
par_joueur AS (
  SELECT
    p.name                                                                   AS joueur,
    LEAST(65, pr.base + COALESCE(p.extra_games, 0))                          AS limite,
    COUNT(g.id)                                                              AS jouees,
    GREATEST(0, LEAST(65, pr.base + COALESCE(p.extra_games, 0)) - COUNT(g.id)) AS restantes,
    COUNT(g.id) FILTER (WHERE g.created_at >= now() - INTERVAL '14 days')    AS rythme_14j,
    MAX(g.created_at)::date                                                  AS derniere_game,
    pr.base, pr.fin_prevue, pr.fin_prolongee
  FROM players p
  CROSS JOIN params pr
  LEFT JOIN games g ON g.player_id = p.id
  GROUP BY p.name, p.extra_games, pr.base, pr.fin_prevue, pr.fin_prolongee
)
SELECT
  joueur,
  jouees,
  limite,
  restantes,
  CASE
    WHEN jouees >= base       THEN 'Fini'
    WHEN jouees >= base - 2   THEN 'Quasiment fini'
    WHEN restantes >= 15      THEN 'Encore beaucoup'
    ELSE                           'Bien avancé'
  END                                                                        AS statut,
  rythme_14j,
  derniere_game,
  -- projection au rythme des 14 derniers jours (games/jour × jours restants)
  LEAST(limite, jouees + ROUND(rythme_14j / 14.0 * GREATEST(0, fin_prevue - CURRENT_DATE)))     AS projection_30_09,
  LEAST(limite, jouees + ROUND(rythme_14j / 14.0 * GREATEST(0, fin_prolongee - CURRENT_DATE)))  AS projection_15_10,
  (jouees + ROUND(rythme_14j / 14.0 * GREATEST(0, fin_prevue - CURRENT_DATE)))    >= base AS finit_au_30_09,
  (jouees + ROUND(rythme_14j / 14.0 * GREATEST(0, fin_prolongee - CURRENT_DATE))) >= base AS finit_au_15_10
FROM par_joueur
ORDER BY jouees DESC, joueur;


-- ---------------------------------------------------------------------------
-- REQUÊTE 4 — IMPACT DE LA PROLONGATION : combien de joueurs de plus finiraient ?
-- ---------------------------------------------------------------------------
-- Compare, au rythme actuel de chacun, le nombre de finisseurs au 30/09 vs au 15/10.
-- C'est LE chiffre pour trancher : si la prolongation ne fait finir presque personne
-- de plus, elle ne sert qu'aux joueurs déjà à 60.
WITH params AS (
  SELECT
    COALESCE((SELECT value::int FROM app_flags WHERE key = 'maxGames'), 60) AS base,
    DATE '2026-09-30' AS fin_prevue,
    DATE '2026-10-15' AS fin_prolongee
),
par_joueur AS (
  SELECT
    COUNT(g.id)                                                              AS jouees,
    COUNT(g.id) FILTER (WHERE g.created_at >= now() - INTERVAL '14 days')    AS rythme_14j,
    pr.base, pr.fin_prevue, pr.fin_prolongee
  FROM players p
  CROSS JOIN params pr
  LEFT JOIN games g ON g.player_id = p.id
  GROUP BY p.id, pr.base, pr.fin_prevue, pr.fin_prolongee
),
proj AS (
  SELECT
    jouees >= base                                                                          AS fini_aujourdhui,
    jouees + ROUND(rythme_14j / 14.0 * GREATEST(0, fin_prevue - CURRENT_DATE))    >= base    AS fini_30_09,
    jouees + ROUND(rythme_14j / 14.0 * GREATEST(0, fin_prolongee - CURRENT_DATE)) >= base    AS fini_15_10,
    rythme_14j > 0                                                                          AS actif_14j
  FROM par_joueur
)
SELECT
  COUNT(*)                                                     AS nb_joueurs,
  COUNT(*) FILTER (WHERE actif_14j)                            AS actifs_14_derniers_jours,
  COUNT(*) FILTER (WHERE fini_aujourdhui)                      AS finis_aujourdhui,
  COUNT(*) FILTER (WHERE fini_30_09)                           AS finiraient_au_30_09,
  COUNT(*) FILTER (WHERE fini_15_10)                           AS finiraient_au_15_10,
  COUNT(*) FILTER (WHERE fini_15_10 AND NOT fini_30_09)        AS gagnes_par_la_prolongation,
  ROUND(100.0 * COUNT(*) FILTER (WHERE fini_30_09) / COUNT(*), 1) AS pct_finis_30_09,
  ROUND(100.0 * COUNT(*) FILTER (WHERE fini_15_10) / COUNT(*), 1) AS pct_finis_15_10
FROM proj;


-- ---------------------------------------------------------------------------
-- REQUÊTE 5 — RYTHME GLOBAL : games saisies par semaine (la ligue ralentit-elle ?)
-- ---------------------------------------------------------------------------
SELECT
  date_trunc('week', created_at)::date                AS semaine,
  COUNT(*)                                            AS games,
  COUNT(DISTINCT player_id)                           AS joueurs_actifs,
  ROUND(COUNT(*)::numeric / COUNT(DISTINCT player_id), 1) AS games_par_joueur_actif
FROM games
GROUP BY 1
ORDER BY 1;
