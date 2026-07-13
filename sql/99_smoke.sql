SELECT `Sector`,
       round(MEASURE(`Gross Written Premium`) / 1e6, 1) AS gwp_m,
       round(MEASURE(`Loss Ratio`), 3) AS loss_ratio,
       MEASURE(`Policy Count`) AS policies
FROM mv_underwriting
WHERE `Year` = 2025
GROUP BY ALL
ORDER BY gwp_m DESC;
