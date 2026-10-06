SELECT 
    keyHex,
    CONCAT(
        FLOOR(CAST(CONV(keyHex, 16, 10) AS UNSIGNED) / 65536), 
        ',', 
        CAST(CONV(keyHex, 16, 10) AS UNSIGNED) % 65536
    ) AS card_formatted
FROM (SELECT '76DA8D' AS keyHex) AS t;
