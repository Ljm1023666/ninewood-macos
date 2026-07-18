-- 08 找人：把渲染图预览人物写入数据库（前端 UI 不动，功能走真实 API）
-- 固定 UUID，便于客户端按名单对齐

DO $$
DECLARE
  people JSONB := '[
    {"id":"00000008-0001-4000-8000-000000000001","phone":"19900008001","name":"陈知远","level":"ADVANCED","orders":128,"score":98,"city":"310000","region":"上海","tags":["产品策略","用户研究","数据分析"],"bio":"8 年互联网产品经验，擅长把模糊目标拆成可验证路径。近三年以匿名协作完成多轮产品定位、用户研究与增长实验，重视过程透明与可复用交付。","rating":4.95},
    {"id":"00000008-0002-4000-8000-000000000002","phone":"19900008002","name":"周屿","level":"ADVANCED","orders":46,"score":96,"city":"330100","region":"杭州","tags":["品牌升级","图标设计","多端适配"],"bio":"产品与品牌视觉设计，重视过程透明与可靠交付。擅长从风格探索到多端图标与规范落地。","rating":4.92},
    {"id":"00000008-0003-4000-8000-000000000003","phone":"19900008003","name":"程野","level":"INTERMEDIATE","orders":31,"score":92,"city":"110000","region":"北京","tags":["用户访谈","研究报告","内容整理"],"bio":"用户研究与内容整理，擅长把访谈材料沉淀为可执行洞察。","rating":4.85},
    {"id":"00000008-0004-4000-8000-000000000004","phone":"19900008004","name":"乔安","level":"INTERMEDIATE","orders":19,"score":90,"city":"440300","region":"深圳","tags":["数据分析","指标设计","研究报告"],"bio":"数据分析和研究报告，关注指标口径与可读表达。","rating":4.80},
    {"id":"00000008-0005-4000-8000-000000000005","phone":"19900008005","name":"林夏","level":"ADVANCED","orders":67,"score":97,"city":"310000","region":"上海","tags":["产品设计","交互设计","原型"],"bio":"产品设计与交互，擅长把复杂流程做成清晰可演示的原型与规范。","rating":4.93},
    {"id":"00000008-0006-4000-8000-000000000006","phone":"19900008006","name":"许言","level":"INTERMEDIATE","orders":42,"score":93,"city":"510100","region":"成都","tags":["内容策略","文案","品牌叙事"],"bio":"内容策略与品牌叙事，帮助产品把价值讲清楚。","rating":4.88},
    {"id":"00000008-0007-4000-8000-000000000007","phone":"19900008007","name":"方舟","level":"ADVANCED","orders":58,"score":94,"city":"440100","region":"广州","tags":["全栈开发","接口联调","上线交付"],"bio":"全栈开发与上线交付，重视可维护性与交接文档。","rating":4.86},
    {"id":"00000008-0008-4000-8000-000000000008","phone":"19900008008","name":"张默","level":"INTERMEDIATE","orders":27,"score":91,"city":"330100","region":"杭州","tags":["增长实验","渠道投放","留存"],"bio":"增长实验与渠道投放，用小步快跑验证获客与留存假设。","rating":4.78}
  ]'::jsonb;
  item JSONB;
  uid TEXT;
  tags TEXT[];
  region_id INT;
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements(people)
  LOOP
    uid := item->>'id';
    SELECT ARRAY(SELECT jsonb_array_elements_text(item->'tags')) INTO tags;
    region_id := (item->>'city')::INT;

    INSERT INTO "User" (
      id, phone, nickname, "passwordHash", "avatarUrl", "coverUrl", "demandCardCoverUrl",
      "cityCode", "ipRegion", "certificationLevel", "creditScore", "completedOrders",
      bio, "serviceTags", "snatchCredits", points, "createdAt", "updatedAt"
    ) VALUES (
      uid,
      item->>'phone',
      item->>'name',
      '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZRGdjGj/n3.rsF.Hr/pqK.zqKzqKz', -- placeholder; login not required for browse
      '/uploads/avatars/avatar_0' || ((abs(hashtext(uid)) % 9) + 1) || '.jpeg',
      '/uploads/covers/cover_' || lpad(((abs(hashtext(uid)) % 30) + 1)::text, 2, '0') || '.jpg',
      '/uploads/card-covers/100' || lpad(((abs(hashtext(uid)) % 20) + 1)::text, 2, '0') || '.jpg',
      item->>'city',
      item->>'region',
      (item->>'level')::"CertLevel",
      (item->>'score')::INT,
      (item->>'orders')::INT,
      item->>'bio',
      tags,
      5,
      1000000,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
      nickname = EXCLUDED.nickname,
      bio = EXCLUDED.bio,
      "certificationLevel" = EXCLUDED."certificationLevel",
      "creditScore" = EXCLUDED."creditScore",
      "completedOrders" = EXCLUDED."completedOrders",
      "cityCode" = EXCLUDED."cityCode",
      "ipRegion" = EXCLUDED."ipRegion",
      "serviceTags" = EXCLUDED."serviceTags",
      "updatedAt" = NOW();

    -- phone unique: if phone taken by other id, keep existing phone on conflict by phone
    UPDATE "User" SET phone = item->>'phone'
    WHERE id = uid AND NOT EXISTS (
      SELECT 1 FROM "User" u2 WHERE u2.phone = item->>'phone' AND u2.id <> uid
    );

    INSERT INTO "CertifiedProvider" ("userId", tags, "regionId", "avgRating", "totalCompleted", "verifiedAt")
    VALUES (
      uid,
      tags,
      region_id,
      (item->>'rating')::FLOAT,
      (item->>'orders')::INT,
      NOW()
    )
    ON CONFLICT ("userId") DO UPDATE SET
      tags = EXCLUDED.tags,
      "regionId" = EXCLUDED."regionId",
      "avgRating" = EXCLUDED."avgRating",
      "totalCompleted" = EXCLUDED."totalCompleted";
  END LOOP;
END $$;
