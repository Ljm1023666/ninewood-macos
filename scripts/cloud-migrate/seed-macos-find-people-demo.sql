-- macOS 找人联调：认证服务者样本（视觉设计 / 用户研究 / 产品）
-- CertifiedProvider PK = userId

DO $$
DECLARE
  u_a TEXT := '29844721-ff7f-4340-b60d-d68a73c5d6c7'; -- 13884283997 → 林夏
  u_b TEXT;
  u_c TEXT;
  u_d TEXT;
BEGIN
  UPDATE "User"
  SET "certificationLevel" = 'ADVANCED',
      nickname = '林夏',
      bio = '产品研究与用户访谈顾问。擅长早期验证、洞察报告与服务卡整理，可远程或上海线下。',
      "creditScore" = 96,
      "completedOrders" = 48,
      "cityCode" = '310000',
      "ipRegion" = '上海',
      "avatarUrl" = COALESCE("avatarUrl", '/uploads/avatars/avatar_02.jpeg'),
      "coverUrl" = COALESCE("coverUrl", '/uploads/covers/cover_12.jpg'),
      "demandCardCoverUrl" = COALESCE("demandCardCoverUrl", '/uploads/card-covers/10012.jpg'),
      "serviceTags" = ARRAY['用户研究', '用户访谈', '产品研究', '视觉设计']
  WHERE id = u_a;

  INSERT INTO "CertifiedProvider" ("userId", tags, "regionId", "avgRating", "totalCompleted", "verifiedAt")
  VALUES (u_a, ARRAY['用户研究', '用户访谈', '产品研究'], 310000, 4.9, 48, NOW())
  ON CONFLICT ("userId") DO UPDATE SET
    tags = EXCLUDED.tags,
    "regionId" = EXCLUDED."regionId",
    "avgRating" = EXCLUDED."avgRating",
    "totalCompleted" = EXCLUDED."totalCompleted";

  SELECT id INTO u_b FROM "User"
  WHERE "certificationLevel" IN ('INTERMEDIATE', 'ADVANCED') AND id <> u_a
  ORDER BY "completedOrders" DESC NULLS LAST
  LIMIT 1;

  SELECT id INTO u_c FROM "User"
  WHERE "certificationLevel" IN ('INTERMEDIATE', 'ADVANCED')
    AND id NOT IN (u_a, COALESCE(u_b, u_a))
  ORDER BY "creditScore" DESC NULLS LAST
  LIMIT 1;

  SELECT id INTO u_d FROM "User"
  WHERE "certificationLevel" IN ('BASIC', 'INTERMEDIATE', 'ADVANCED')
    AND id NOT IN (u_a, COALESCE(u_b, u_a), COALESCE(u_c, u_a))
  ORDER BY "completedOrders" DESC NULLS LAST
  LIMIT 1;

  IF u_b IS NOT NULL THEN
    UPDATE "User" SET
      bio = COALESCE(NULLIF(bio, ''), '品牌视觉与产品图标设计，重视过程透明与可靠交付。'),
      "serviceTags" = CASE WHEN cardinality(COALESCE("serviceTags", ARRAY[]::text[])) = 0
        THEN ARRAY['视觉设计', '图标设计', '品牌升级'] ELSE "serviceTags" END,
      "cityCode" = COALESCE("cityCode", '310000'),
      "ipRegion" = COALESCE("ipRegion", '上海')
    WHERE id = u_b;
    INSERT INTO "CertifiedProvider" ("userId", tags, "regionId", "avgRating", "totalCompleted", "verifiedAt")
    VALUES (u_b, ARRAY['视觉设计', '图标设计', '品牌升级'], 310000, 4.8, 36, NOW())
    ON CONFLICT ("userId") DO UPDATE SET
      tags = EXCLUDED.tags, "regionId" = 310000, "avgRating" = EXCLUDED."avgRating";
  END IF;

  IF u_c IS NOT NULL THEN
    UPDATE "User" SET
      bio = COALESCE(NULLIF(bio, ''), '增长实验与渠道投放，用小步快跑验证获客与留存假设。'),
      "serviceTags" = CASE WHEN cardinality(COALESCE("serviceTags", ARRAY[]::text[])) = 0
        THEN ARRAY['增长实验', '渠道投放'] ELSE "serviceTags" END,
      "cityCode" = COALESCE("cityCode", '330100'),
      "ipRegion" = COALESCE("ipRegion", '杭州')
    WHERE id = u_c;
    INSERT INTO "CertifiedProvider" ("userId", tags, "regionId", "avgRating", "totalCompleted", "verifiedAt")
    VALUES (u_c, ARRAY['增长实验', '渠道投放', '留存'], 330100, 4.7, 27, NOW())
    ON CONFLICT ("userId") DO UPDATE SET tags = EXCLUDED.tags, "avgRating" = EXCLUDED."avgRating";
  END IF;

  IF u_d IS NOT NULL THEN
    UPDATE "User" SET
      bio = COALESCE(NULLIF(bio, ''), '短视频脚本与分镜创作，适配种草与转化两类节奏。'),
      "serviceTags" = CASE WHEN cardinality(COALESCE("serviceTags", ARRAY[]::text[])) = 0
        THEN ARRAY['内容创作', '短视频'] ELSE "serviceTags" END,
      "cityCode" = COALESCE("cityCode", '110000'),
      "ipRegion" = COALESCE("ipRegion", '北京')
    WHERE id = u_d;
    INSERT INTO "CertifiedProvider" ("userId", tags, "regionId", "avgRating", "totalCompleted", "verifiedAt")
    VALUES (u_d, ARRAY['内容创作', '短视频', '脚本'], 110000, 4.85, 31, NOW())
    ON CONFLICT ("userId") DO UPDATE SET tags = EXCLUDED.tags, "avgRating" = EXCLUDED."avgRating";
  END IF;
END $$;
