-- 确保发布联调账号点数充足（19900001234）
UPDATE "User"
SET points = GREATEST(points, 1000000)
WHERE phone = '19900001234';
