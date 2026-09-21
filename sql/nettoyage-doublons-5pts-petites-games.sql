-- ============================================================================
-- Nettoyage des +5 pts « petites games » appliqués plusieurs fois à la même game
-- ============================================================================
-- Contexte : avant le correctif, chaque tirage « +5 pts petites games » de la Roue
-- Commu rajoutait +5 au score de TOUTES les games < 5 kills, même celles déjà
-- bonifiées. Une game touchée N fois porte donc N fois la mention
-- « +5pts (< 5 kills) » dans sa note et N×5 pts de trop... moins 5 (le premier
-- bonus est légitime). Ce script ne garde qu'un seul +5 par game.
--
-- À exécuter dans l'éditeur SQL Supabase. Étape 1 = lecture seule, étape 2 = correction.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- ÉTAPE 1a — DÉTAIL PAR GAME : quelles games sont en doublon, et combien on retire
-- ---------------------------------------------------------------------------
WITH doublons AS (
  SELECT
    g.id,
    g.player_id,
    p.name                                                                    AS joueur,
    g.kills,
    g.score                                                                   AS score_actuel,
    g.note,
    g.game_date,
    (length(g.note) - length(replace(g.note, '+5pts (< 5 kills)', '')))
      / length('+5pts (< 5 kills)')                                           AS nb_bonus
  FROM games g
  JOIN players p ON p.id = g.player_id
  WHERE g.note LIKE '%+5pts (< 5 kills)%'
)
SELECT
  joueur,
  id                        AS game_id,
  game_date,
  kills,
  nb_bonus,
  (nb_bonus - 1) * 5        AS pts_retires,
  score_actuel,
  score_actuel - (nb_bonus - 1) * 5 AS score_corrige,
  note
FROM doublons
WHERE nb_bonus > 1
ORDER BY joueur, game_date, id;


-- ---------------------------------------------------------------------------
-- ÉTAPE 1b — RÉSUMÉ PAR JOUEUR : combien de games concernées et combien il perd
-- ---------------------------------------------------------------------------
WITH doublons AS (
  SELECT
    g.player_id,
    p.name AS joueur,
    (length(g.note) - length(replace(g.note, '+5pts (< 5 kills)', '')))
      / length('+5pts (< 5 kills)') AS nb_bonus
  FROM games g
  JOIN players p ON p.id = g.player_id
  WHERE g.note LIKE '%+5pts (< 5 kills)%'
)
SELECT
  joueur,
  count(*)                       AS games_en_doublon,
  sum(nb_bonus - 1)              AS bonus_en_trop,
  sum((nb_bonus - 1) * 5)        AS pts_perdus
FROM doublons
WHERE nb_bonus > 1
GROUP BY joueur
ORDER BY pts_perdus DESC, joueur;


-- ---------------------------------------------------------------------------
-- ÉTAPE 2 — CORRECTION : ne garder qu'un seul +5 par game
-- ---------------------------------------------------------------------------
-- Pour chaque game en doublon :
--   • score = score - 5 × (nb_bonus - 1)
--   • note  = note sans aucune mention « +5pts (< 5 kills) », puis une seule remise en fin
-- Le RETURNING affiche ce qui a été modifié. L'étape 1a montre exactement le même
-- résultat AVANT modification : vérifie-la d'abord, cette étape est définitive.
-- ---------------------------------------------------------------------------
WITH doublons AS (
  SELECT
    g.id,
    g.note,
    (length(g.note) - length(replace(g.note, '+5pts (< 5 kills)', '')))
      / length('+5pts (< 5 kills)') AS nb_bonus
  FROM games g
  WHERE g.note LIKE '%+5pts (< 5 kills)%'
),
corrections AS (
  SELECT
    id,
    (nb_bonus - 1) * 5 AS pts_retires,
    -- 1. on supprime toutes les mentions, avec leur séparateur « · » éventuel
    -- 2. on nettoie un séparateur orphelin en tête ou en fin
    -- 3. on remet exactement une mention
    CASE
      WHEN btrim(regexp_replace(regexp_replace(note, '( · )?\+5pts \(< 5 kills\)', '', 'g'), '^( · )+|( · )+$', '', 'g')) = ''
        THEN '+5pts (< 5 kills)'
      ELSE btrim(regexp_replace(regexp_replace(note, '( · )?\+5pts \(< 5 kills\)', '', 'g'), '^( · )+|( · )+$', '', 'g')) || ' · +5pts (< 5 kills)'
    END AS nouvelle_note
  FROM doublons
  WHERE nb_bonus > 1
)
UPDATE games g
SET
  score = g.score - c.pts_retires,
  note  = c.nouvelle_note
FROM corrections c, players p
WHERE g.id = c.id
  AND p.id = g.player_id
RETURNING
  p.name          AS joueur,
  g.id            AS game_id,
  g.kills,
  c.pts_retires,
  g.score         AS score_corrige,
  g.note          AS note_corrigee;


-- ---------------------------------------------------------------------------
-- ÉTAPE 3 — CONTRÔLE : il ne doit plus rester aucune game avec plus d'un bonus
-- ---------------------------------------------------------------------------
SELECT count(*) AS games_encore_en_doublon
FROM games
WHERE (length(note) - length(replace(note, '+5pts (< 5 kills)', '')))
      / length('+5pts (< 5 kills)') > 1;
