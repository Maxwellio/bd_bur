-- Выгрузка нарядов за 2026 год по операциям spr_oper 37594, 37618, 37595, 587.
-- В файле шесть отдельных запросов: запускать в Maestro по одному.
--
-- 1. Норма и факт по каждой операции внутри наряда (не итог всего наряда).
--    Сумма строк выполнения с этим oper, burnar.vipolnenie_norm, prnum = 2
-- («на объём» и колонка «Факт»). В базе минуты, в выгрузке часы.
-- Повтор операции в одном наряде суммируется.
-- Норма «на единицу измерения» — тот же vip_key, prnum = 1.
--
-- Скважина / куст / месторождение — burnar.znparams:
--   149 — скважина, 470 — куст, 5 — месторождение.
-- Дискретное значение (znval) раскрывается через public.common_spr.nm.
--
-- struktura — название подразделения burnar.org_stru с id 5, 6, 7 или 8,
-- к которому относится наряд. Бригада: defnar.ownernar -> spr_workers.org,
-- дальше вверх по parent, пока не встретится один из этих id.
-- Имена столбцов латиницей: PostgreSQL Maestro портит кириллицу.
--
-- Наряд попадает в 2026, если дата начала выполнения (defnarvip.begdate)
-- в 2026 или любой период выполнения пересекает 2026,
-- и в выполнении есть хотя бы одна из этих операций.
-- Отбор по дате создания: заменить WHERE на
--   d.createdate >= DATE '2026-01-01' AND d.createdate < DATE '2027-01-01'.

WITH RECURSIVE org_chain AS (
    SELECT
        o.id        AS org_id,
        o.id        AS node_id,
        o.parent,
        o.nm,
        1           AS steps_up
    FROM burnar.org_stru o

    UNION ALL

    SELECT
        c.org_id,
        p.id,
        p.parent,
        p.nm,
        c.steps_up + 1
    FROM org_chain c
    JOIN burnar.org_stru p ON p.id = c.parent
    WHERE c.parent IS NOT NULL
      AND c.parent <> 0
      AND c.steps_up < 30
),
org_hit AS (
    SELECT DISTINCT ON (org_id)
        org_id,
        nm AS struktura
    FROM org_chain
    WHERE node_id IN (5, 6, 7, 8)
    ORDER BY org_id, steps_up
),
zn AS (
    SELECT
        z.defnar,
        z.parcode,
        CASE
            WHEN z.znval IS NOT NULL THEN cs.nm
            WHEN z.val IS NOT NULL THEN z.val::varchar
            ELSE z.valstr
        END AS val_nm,
        ROW_NUMBER() OVER (
            PARTITION BY z.defnar, z.parcode
            ORDER BY z.prnum
        ) AS rn
    FROM burnar.znparams z
    LEFT JOIN public.common_spr cs ON cs.id = z.znval
    WHERE z.parcode IN (149, 470, 5)
),
ops AS (
    SELECT
        o.narkey,
        ROUND(SUM(n.norma) FILTER (WHERE o.oper = 37594) / 60, 2) AS norma_37594,
        ROUND(SUM(n.fact)  FILTER (WHERE o.oper = 37594) / 60, 2) AS fakt_37594,
        ROUND(SUM(n.norma) FILTER (WHERE o.oper = 37618) / 60, 2) AS norma_37618,
        ROUND(SUM(n.fact)  FILTER (WHERE o.oper = 37618) / 60, 2) AS fakt_37618,
        ROUND(SUM(n.norma) FILTER (WHERE o.oper = 37595) / 60, 2) AS norma_37595,
        ROUND(SUM(n.fact)  FILTER (WHERE o.oper = 37595) / 60, 2) AS fakt_37595,
        ROUND(SUM(n.norma) FILTER (WHERE o.oper = 587) / 60, 2) AS norma_587,
        ROUND(SUM(n.fact)  FILTER (WHERE o.oper = 587) / 60, 2) AS fakt_587
    FROM burnar.vipolnenie_oper o
    LEFT JOIN burnar.vipolnenie_norm n
           ON n.vip_key = o.key
          AND n.prnum = 2
    WHERE o.oper IN (37594, 37618, 37595, 587)
    GROUP BY o.narkey
)
SELECT
    d.nm            AS nazvanie_naryada,
    skv.val_nm      AS skvazhina,
    kust.val_nm     AS kust,
    mest.val_nm     AS mestorozhdenie,
    oh.struktura    AS struktura,
    ops.norma_37594 AS norma_37594,
    ops.fakt_37594  AS fakt_37594,
    ops.norma_37618 AS norma_37618,
    ops.fakt_37618  AS fakt_37618,
    ops.norma_37595 AS norma_37595,
    ops.fakt_37595  AS fakt_37595,
    ops.norma_587   AS norma_587,
    ops.fakt_587    AS fakt_587
FROM ops
JOIN burnar.defnar d
  ON d.key = ops.narkey
JOIN burnar.spr_workers s
  ON s.key = d.ownernar
LEFT JOIN org_hit oh
  ON oh.org_id = s.org
LEFT JOIN burnar.defnarvip v
  ON v.narkey = d.key
LEFT JOIN zn skv
  ON skv.defnar = d.key AND skv.parcode = 149 AND skv.rn = 1
LEFT JOIN zn kust
  ON kust.defnar = d.key AND kust.parcode = 470 AND kust.rn = 1
LEFT JOIN zn mest
  ON mest.defnar = d.key AND mest.parcode = 5 AND mest.rn = 1
WHERE (
        v.begdate >= DATE '2026-01-01'
    AND v.begdate <  DATE '2027-01-01'
)
OR EXISTS (
    SELECT 1
    FROM burnar.vipolnenie_period p
    WHERE p.narkey = d.key
      AND p.begoperdate <  DATE '2027-01-01'
      AND p.outoperdate >= DATE '2026-01-01'
)
ORDER BY d.nm, d.key;

-- 2. Все наряды за 2026, в выполнении которых есть хотя бы одна из этих операций.
--    Без нормы и факта: одна строка на наряд, operacii — какие из четырёх кодов в нём есть.
WITH RECURSIVE org_chain AS (
    SELECT
        o.id        AS org_id,
        o.id        AS node_id,
        o.parent,
        o.nm,
        1           AS steps_up
    FROM burnar.org_stru o

    UNION ALL

    SELECT
        c.org_id,
        p.id,
        p.parent,
        p.nm,
        c.steps_up + 1
    FROM org_chain c
    JOIN burnar.org_stru p ON p.id = c.parent
    WHERE c.parent IS NOT NULL
      AND c.parent <> 0
      AND c.steps_up < 30
),
org_hit AS (
    SELECT DISTINCT ON (org_id)
        org_id,
        nm AS struktura
    FROM org_chain
    WHERE node_id IN (5, 6, 7, 8)
    ORDER BY org_id, steps_up
),
zn AS (
    SELECT
        z.defnar,
        z.parcode,
        CASE
            WHEN z.znval IS NOT NULL THEN cs.nm
            WHEN z.val IS NOT NULL THEN z.val::varchar
            ELSE z.valstr
        END AS val_nm,
        ROW_NUMBER() OVER (
            PARTITION BY z.defnar, z.parcode
            ORDER BY z.prnum
        ) AS rn
    FROM burnar.znparams z
    LEFT JOIN public.common_spr cs ON cs.id = z.znval
    WHERE z.parcode IN (149, 470, 5)
),
naryady AS (
    SELECT
        o.narkey,
        string_agg(DISTINCT o.oper::varchar, ', ' ORDER BY o.oper::varchar) AS operacii
    FROM burnar.vipolnenie_oper o
    WHERE o.oper IN (37594, 37618, 37595, 587)
    GROUP BY o.narkey
)
SELECT
    d.key           AS kod_naryada,
    d.nm            AS nazvanie_naryada,
    skv.val_nm      AS skvazhina,
    kust.val_nm     AS kust,
    mest.val_nm     AS mestorozhdenie,
    oh.struktura    AS struktura,
    v.begdate       AS data_nachala,
    n.operacii      AS operacii
FROM naryady n
JOIN burnar.defnar d
  ON d.key = n.narkey
JOIN burnar.spr_workers s
  ON s.key = d.ownernar
LEFT JOIN org_hit oh
  ON oh.org_id = s.org
LEFT JOIN burnar.defnarvip v
  ON v.narkey = d.key
LEFT JOIN zn skv
  ON skv.defnar = d.key AND skv.parcode = 149 AND skv.rn = 1
LEFT JOIN zn kust
  ON kust.defnar = d.key AND kust.parcode = 470 AND kust.rn = 1
LEFT JOIN zn mest
  ON mest.defnar = d.key AND mest.parcode = 5 AND mest.rn = 1
WHERE (
        v.begdate >= DATE '2026-01-01'
    AND v.begdate <  DATE '2027-01-01'
)
OR EXISTS (
    SELECT 1
    FROM burnar.vipolnenie_period p
    WHERE p.narkey = d.key
      AND p.begoperdate <  DATE '2027-01-01'
      AND p.outoperdate >= DATE '2026-01-01'
)
ORDER BY d.nm, d.key;

-- 3. Норма и факт по каждой строке операции за 2026, без наряда.
--    Строки не складываются. Наряд нужен только чтобы оставить работы 2026 года.
SELECT
    o."key" AS kod_stroki,
    o.oper  AS kod_operacii,
    so.nm   AS nazvanie_operacii,
    ROUND(n.norma / 60, 2) AS norma,
    ROUND(n.fact / 60, 2)  AS fakt
FROM burnar.vipolnenie_oper o
JOIN burnar.defnar d
  ON d.key = o.narkey
LEFT JOIN burnar.defnarvip v
  ON v.narkey = d.key
LEFT JOIN burnar.vipolnenie_norm n
  ON n.vip_key = o.key
 AND n.prnum = 2
LEFT JOIN public.spr_oper so
  ON so."key" = o.oper
WHERE o.oper IN (37594, 37618, 37595, 587)
  AND (
        (
            v.begdate >= DATE '2026-01-01'
        AND v.begdate <  DATE '2027-01-01'
        )
        OR EXISTS (
            SELECT 1
            FROM burnar.vipolnenie_period p
            WHERE p.narkey = d.key
              AND p.begoperdate <  DATE '2027-01-01'
              AND p.outoperdate >= DATE '2026-01-01'
        )
      )
ORDER BY o.oper, o."key";

-- 4. Как запрос 1, но повторы одной операции в наряде не складываются:
--    каждая строка выполнения выводится отдельно.
--    В строке заполнена только пара norma/fakt её операции.
WITH RECURSIVE org_chain AS (
    SELECT
        o.id        AS org_id,
        o.id        AS node_id,
        o.parent,
        o.nm,
        1           AS steps_up
    FROM burnar.org_stru o

    UNION ALL

    SELECT
        c.org_id,
        p.id,
        p.parent,
        p.nm,
        c.steps_up + 1
    FROM org_chain c
    JOIN burnar.org_stru p ON p.id = c.parent
    WHERE c.parent IS NOT NULL
      AND c.parent <> 0
      AND c.steps_up < 30
),
org_hit AS (
    SELECT DISTINCT ON (org_id)
        org_id,
        nm AS struktura
    FROM org_chain
    WHERE node_id IN (5, 6, 7, 8)
    ORDER BY org_id, steps_up
),
zn AS (
    SELECT
        z.defnar,
        z.parcode,
        CASE
            WHEN z.znval IS NOT NULL THEN cs.nm
            WHEN z.val IS NOT NULL THEN z.val::varchar
            ELSE z.valstr
        END AS val_nm,
        ROW_NUMBER() OVER (
            PARTITION BY z.defnar, z.parcode
            ORDER BY z.prnum
        ) AS rn
    FROM burnar.znparams z
    LEFT JOIN public.common_spr cs ON cs.id = z.znval
    WHERE z.parcode IN (149, 470, 5)
)
SELECT
    d.nm AS nazvanie_naryada,
    skv.val_nm AS skvazhina,
    kust.val_nm AS kust,
    mest.val_nm AS mestorozhdenie,
    oh.struktura AS struktura,
    o."key" AS kod_stroki,
    o.oper AS kod_operacii,
    CASE WHEN o.oper = 37594 THEN ROUND(n.norma / 60, 2) END AS norma_37594,
    CASE WHEN o.oper = 37594 THEN ROUND(n.fact / 60, 2) END AS fakt_37594,
    CASE WHEN o.oper = 37618 THEN ROUND(n.norma / 60, 2) END AS norma_37618,
    CASE WHEN o.oper = 37618 THEN ROUND(n.fact / 60, 2) END AS fakt_37618,
    CASE WHEN o.oper = 37595 THEN ROUND(n.norma / 60, 2) END AS norma_37595,
    CASE WHEN o.oper = 37595 THEN ROUND(n.fact / 60, 2) END AS fakt_37595,
    CASE WHEN o.oper = 587 THEN ROUND(n.norma / 60, 2) END AS norma_587,
    CASE WHEN o.oper = 587 THEN ROUND(n.fact / 60, 2) END AS fakt_587
FROM burnar.vipolnenie_oper o
JOIN burnar.defnar d
  ON d.key = o.narkey
JOIN burnar.spr_workers s
  ON s.key = d.ownernar
LEFT JOIN org_hit oh
  ON oh.org_id = s.org
LEFT JOIN burnar.defnarvip v
  ON v.narkey = d.key
LEFT JOIN burnar.vipolnenie_norm n
  ON n.vip_key = o."key"
 AND n.prnum = 2
LEFT JOIN zn skv
  ON skv.defnar = d.key AND skv.parcode = 149 AND skv.rn = 1
LEFT JOIN zn kust
  ON kust.defnar = d.key AND kust.parcode = 470 AND kust.rn = 1
LEFT JOIN zn mest
  ON mest.defnar = d.key AND mest.parcode = 5 AND mest.rn = 1
WHERE o.oper IN (37594, 37618, 37595, 587)
  AND (
        (
            v.begdate >= DATE '2026-01-01'
        AND v.begdate <  DATE '2027-01-01'
        )
        OR EXISTS (
            SELECT 1
            FROM burnar.vipolnenie_period p
            WHERE p.narkey = d.key
              AND p.begoperdate <  DATE '2027-01-01'
              AND p.outoperdate >= DATE '2026-01-01'
        )
      )
ORDER BY d.nm, d.key, o.oper, o."key";

-- 5. Как запрос 4, но 2026 проверяется у строки операции, а не у наряда.
--    Строка остаётся, если vipolnenie_oper.begoperdate в 2026
--    или период этой строки (vipolnenie_oper.period) пересекает 2026.
WITH RECURSIVE org_chain AS (
    SELECT
        o.id        AS org_id,
        o.id        AS node_id,
        o.parent,
        o.nm,
        1           AS steps_up
    FROM burnar.org_stru o

    UNION ALL

    SELECT
        c.org_id,
        p.id,
        p.parent,
        p.nm,
        c.steps_up + 1
    FROM org_chain c
    JOIN burnar.org_stru p ON p.id = c.parent
    WHERE c.parent IS NOT NULL
      AND c.parent <> 0
      AND c.steps_up < 30
),
org_hit AS (
    SELECT DISTINCT ON (org_id)
        org_id,
        nm AS struktura
    FROM org_chain
    WHERE node_id IN (5, 6, 7, 8)
    ORDER BY org_id, steps_up
),
zn AS (
    SELECT
        z.defnar,
        z.parcode,
        CASE
            WHEN z.znval IS NOT NULL THEN cs.nm
            WHEN z.val IS NOT NULL THEN z.val::varchar
            ELSE z.valstr
        END AS val_nm,
        ROW_NUMBER() OVER (
            PARTITION BY z.defnar, z.parcode
            ORDER BY z.prnum
        ) AS rn
    FROM burnar.znparams z
    LEFT JOIN public.common_spr cs ON cs.id = z.znval
    WHERE z.parcode IN (149, 470, 5)
)
SELECT
    d.nm AS nazvanie_naryada,
    skv.val_nm AS skvazhina,
    kust.val_nm AS kust,
    mest.val_nm AS mestorozhdenie,
    oh.struktura AS struktura,
    o."key" AS kod_stroki,
    o.oper AS kod_operacii,
    o.begoperdate AS data_operacii,
    CASE WHEN o.oper = 37594 THEN ROUND(n.norma / 60, 2) END AS norma_37594,
    CASE WHEN o.oper = 37594 THEN ROUND(n.fact / 60, 2) END AS fakt_37594,
    CASE WHEN o.oper = 37618 THEN ROUND(n.norma / 60, 2) END AS norma_37618,
    CASE WHEN o.oper = 37618 THEN ROUND(n.fact / 60, 2) END AS fakt_37618,
    CASE WHEN o.oper = 37595 THEN ROUND(n.norma / 60, 2) END AS norma_37595,
    CASE WHEN o.oper = 37595 THEN ROUND(n.fact / 60, 2) END AS fakt_37595,
    CASE WHEN o.oper = 587 THEN ROUND(n.norma / 60, 2) END AS norma_587,
    CASE WHEN o.oper = 587 THEN ROUND(n.fact / 60, 2) END AS fakt_587
FROM burnar.vipolnenie_oper o
JOIN burnar.defnar d
  ON d.key = o.narkey
JOIN burnar.spr_workers s
  ON s.key = d.ownernar
LEFT JOIN org_hit oh
  ON oh.org_id = s.org
LEFT JOIN burnar.vipolnenie_period per
  ON per."key" = o.period
LEFT JOIN burnar.vipolnenie_norm n
  ON n.vip_key = o."key"
 AND n.prnum = 2
LEFT JOIN zn skv
  ON skv.defnar = d.key AND skv.parcode = 149 AND skv.rn = 1
LEFT JOIN zn kust
  ON kust.defnar = d.key AND kust.parcode = 470 AND kust.rn = 1
LEFT JOIN zn mest
  ON mest.defnar = d.key AND mest.parcode = 5 AND mest.rn = 1
WHERE o.oper IN (37594, 37618, 37595, 587)
  AND (
        (
            o.begoperdate >= DATE '2026-01-01'
        AND o.begoperdate <  DATE '2027-01-01'
        )
        OR (
            per.begoperdate <  DATE '2027-01-01'
        AND per.outoperdate >= DATE '2026-01-01'
        )
      )
ORDER BY d.nm, d.key, o.oper, o."key";

-- 6. Названия операций для заголовков выгрузки.
SELECT "key", nm, shortnm
FROM public.spr_oper
WHERE "key" IN (37594, 37618, 37595, 587);
