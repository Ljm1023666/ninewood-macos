-- 把 macOS 设计稿里的会话 / 群聊 / 关注 / 服务卡 / 圈子成员写入生产库
-- 原则：补数据，不删前端；测试账号 19900001234 登录后应看到丰富真实数据
-- 依赖：seed-macos-find-people-preview.sql 已写入 00000008-0001…0008

DO $$
DECLARE
  tester TEXT := 'a5122abf-6c88-4c76-a14a-6166c0c434db'; -- 19900001234 九木测试
  linxia TEXT := '29844721-ff7f-4340-b60d-d68a73c5d6c7'; -- 13884283997 林夏
  chenshu TEXT := '00000008-0009-4000-8000-000000000009'; -- 陈述（设计稿私聊）
  u_chen TEXT := '00000008-0001-4000-8000-000000000001';
  u_zhou TEXT := '00000008-0002-4000-8000-000000000002';
  u_cheng TEXT := '00000008-0003-4000-8000-000000000003';
  u_qiao TEXT := '00000008-0004-4000-8000-000000000004';
  u_linxia_seed TEXT := '00000008-0005-4000-8000-000000000005';
  u_xu TEXT := '00000008-0006-4000-8000-000000000006';
  u_fang TEXT := '00000008-0007-4000-8000-000000000007';
  u_zhang TEXT := '00000008-0008-4000-8000-000000000008';
  circle_id TEXT;
  peer TEXT;
  merge_rec RECORD;
BEGIN
  -- ── 陈述：设计稿私聊对方 ──────────────────────────────────────────
  INSERT INTO "User" (
    id, phone, nickname, "passwordHash", "avatarUrl", "coverUrl", "demandCardCoverUrl",
    "cityCode", "ipRegion", "certificationLevel", "creditScore", "completedOrders",
    bio, "serviceTags", "snatchCredits", points, "createdAt", "updatedAt"
  ) VALUES (
    chenshu,
    '19900008009',
    '陈述',
    '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZRGdjGj/n3.rsF.Hr/pqK.zqKzqKz',
    '/uploads/avatars/avatar_03.jpeg',
    '/uploads/covers/cover_08.jpg',
    '/uploads/card-covers/10008.jpg',
    '110000',
    '北京',
    'ADVANCED',
    95,
    54,
    '后端与接口联调，擅长把协作链路跑通并交付可维护服务。',
    ARRAY['后端工程', '接口联调', '全栈协作'],
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
    "serviceTags" = EXCLUDED."serviceTags",
    "updatedAt" = NOW();

  INSERT INTO "CertifiedProvider" ("userId", tags, "regionId", "avgRating", "totalCompleted", "verifiedAt")
  VALUES (chenshu, ARRAY['后端工程', '接口联调', '全栈协作'], 110000, 4.9, 54, NOW())
  ON CONFLICT ("userId") DO UPDATE SET
    tags = EXCLUDED.tags,
    "regionId" = EXCLUDED."regionId",
    "avgRating" = EXCLUDED."avgRating",
    "totalCompleted" = EXCLUDED."totalCompleted";

  -- ── 关注：测试账号关注设计人设（含互关种子） ─────────────────────
  FOREACH peer IN ARRAY ARRAY[
    linxia, chenshu, u_chen, u_zhou, u_cheng, u_qiao, u_linxia_seed, u_xu, u_fang, u_zhang
  ]
  LOOP
    INSERT INTO "Follow" (id, "followerId", "followingId", "createdAt")
    VALUES ('macos-follow-' || peer, tester, peer, NOW() - INTERVAL '2 days')
    ON CONFLICT ("followerId", "followingId") DO NOTHING;

    -- 互关：林夏 / 陈述 / 陈知远 / 周屿 回关，撑起「互相关注」条
    IF peer IN (linxia, chenshu, u_chen, u_zhou) THEN
      INSERT INTO "Follow" (id, "followerId", "followingId", "createdAt")
      VALUES ('macos-follow-back-' || peer, peer, tester, NOW() - INTERVAL '1 day')
      ON CONFLICT ("followerId", "followingId") DO NOTHING;
    END IF;
  END LOOP;

  -- ── 私聊：对齐 09 消息设计稿文案 ─────────────────────────────────
  INSERT INTO "Message" (id, "fromUserId", "toUserId", content, type, "isRead", "createdAt")
  VALUES
    ('macos-dm-linxia-1', linxia, tester,
     '你好，我看到你在做消费电子方向的产品研究，想咨询一下有没有档期可以接一个小需求？',
     'TEXT', false, NOW() - INTERVAL '3 hours'),
    ('macos-dm-linxia-2', tester, linxia,
     '有的，这周还能排。你方便发一下需求卡吗？',
     'TEXT', true, NOW() - INTERVAL '2 hours 50 minutes'),
    ('macos-dm-linxia-3', linxia, tester,
     '好的，我整理了一下需求卡，麻烦帮忙看看～',
     'TEXT', false, NOW() - INTERVAL '2 hours 40 minutes'),
    ('macos-dm-linxia-4', tester, linxia,
     '收到，我先看服务框架和样本量，稍后给你反馈。',
     'TEXT', true, NOW() - INTERVAL '2 hours'),
    ('macos-dm-linxia-5', linxia, tester,
     '好的，我看看这个需求卡，稍后给你反馈。',
     'TEXT', false, NOW() - INTERVAL '30 minutes'),
    ('macos-dm-chenshu-1', chenshu, tester,
     '接口联调文档我更新了，你这边客户端可以按新字段对齐。',
     'TEXT', false, NOW() - INTERVAL '5 hours'),
    ('macos-dm-chenshu-2', tester, chenshu,
     '感谢！我会尽快处理。',
     'TEXT', true, NOW() - INTERVAL '4 hours 50 minutes'),
    ('macos-dm-chenshu-3', chenshu, tester,
     '好的，有问题随时 ping 我。',
     'TEXT', false, NOW() - INTERVAL '4 hours'),
    ('macos-dm-zhou-1', u_zhou, tester,
     '图标规范 v2 已导出，含多端尺寸。',
     'TEXT', false, NOW() - INTERVAL '1 day'),
    ('macos-dm-xu-1', u_xu, tester,
     '提案提纲见附件，麻烦过一眼叙事结构。',
     'TEXT', false, NOW() - INTERVAL '2 days'),
    ('macos-dm-fang-1', u_fang, tester,
     'MVP 联调环境好了，可以约一次走查。',
     'TEXT', false, NOW() - INTERVAL '3 days')
  ON CONFLICT (id) DO NOTHING;

  -- ── 群聊：对齐 11 群聊列表标题 ───────────────────────────────────
  INSERT INTO "ConversationMerge" (id, "userId", title, "createdAt") VALUES
    ('macos-merge-product-research', tester, '产品研究协作组', NOW() - INTERVAL '10 days'),
    ('macos-merge-growth', tester, '增长实验小组', NOW() - INTERVAL '9 days'),
    ('macos-merge-design-review', tester, '设计评审会', NOW() - INTERVAL '8 days'),
    ('macos-merge-tech', tester, '技术交流圈', NOW() - INTERVAL '7 days'),
    ('macos-merge-ux-research', tester, '用户研究互助群', NOW() - INTERVAL '6 days'),
    ('macos-merge-brand', tester, '品牌共创工作室', NOW() - INTERVAL '5 days'),
    ('macos-merge-pmo', tester, '项目管理办公室', NOW() - INTERVAL '4 days')
  ON CONFLICT (id) DO NOTHING;

  -- 成员
  INSERT INTO "ConversationMergeMember" ("mergeId", "userId") VALUES
    ('macos-merge-product-research', tester),
    ('macos-merge-product-research', u_linxia_seed),
    ('macos-merge-product-research', u_zhang),
    ('macos-merge-product-research', u_xu),
    ('macos-merge-product-research', u_fang),
    ('macos-merge-growth', tester),
    ('macos-merge-growth', chenshu),
    ('macos-merge-growth', u_linxia_seed),
    ('macos-merge-growth', u_xu),
    ('macos-merge-growth', u_zhang),
    ('macos-merge-design-review', tester),
    ('macos-merge-design-review', u_fang),
    ('macos-merge-design-review', u_zhang),
    ('macos-merge-design-review', u_linxia_seed),
    ('macos-merge-design-review', chenshu),
    ('macos-merge-tech', tester),
    ('macos-merge-tech', chenshu),
    ('macos-merge-tech', u_xu),
    ('macos-merge-tech', u_fang),
    ('macos-merge-tech', u_linxia_seed),
    ('macos-merge-ux-research', tester),
    ('macos-merge-ux-research', u_linxia_seed),
    ('macos-merge-ux-research', chenshu),
    ('macos-merge-ux-research', u_zhang),
    ('macos-merge-ux-research', u_fang),
    ('macos-merge-brand', tester),
    ('macos-merge-brand', u_xu),
    ('macos-merge-brand', u_fang),
    ('macos-merge-brand', u_linxia_seed),
    ('macos-merge-brand', u_zhang),
    ('macos-merge-pmo', tester),
    ('macos-merge-pmo', u_zhang),
    ('macos-merge-pmo', chenshu),
    ('macos-merge-pmo', u_xu),
    ('macos-merge-pmo', u_linxia_seed)
  ON CONFLICT DO NOTHING;

  -- 群消息（最近一条对齐列表预览文案）
  INSERT INTO "Message" (id, "fromUserId", "toUserId", content, type, "isRead", "mergeId", "createdAt")
  VALUES
    ('macos-gm-pr-1', u_zhang, tester, '服务框架图已更新', 'TEXT', false, 'macos-merge-product-research', NOW() - INTERVAL '40 minutes'),
    ('macos-gm-pr-2', tester, u_zhang, '收到，我这边对照需求卡看一下。', 'TEXT', true, 'macos-merge-product-research', NOW() - INTERVAL '35 minutes'),
    ('macos-gm-growth-1', chenshu, tester, '本周转化漏斗已同步', 'TEXT', false, 'macos-merge-growth', NOW() - INTERVAL '2 hours'),
    ('macos-gm-design-1', u_fang, tester, '视觉稿 v3 已上传', 'TEXT', false, 'macos-merge-design-review', NOW() - INTERVAL '5 hours'),
    ('macos-gm-tech-1', chenshu, tester, '接口联调完成', 'TEXT', false, 'macos-merge-tech', NOW() - INTERVAL '1 day'),
    ('macos-gm-ux-1', u_linxia_seed, tester, '招募问卷已发出', 'TEXT', false, 'macos-merge-ux-research', NOW() - INTERVAL '1 day'),
    ('macos-gm-brand-1', u_xu, tester, '提案提纲见附件', 'TEXT', false, 'macos-merge-brand', NOW() - INTERVAL '3 days'),
    ('macos-gm-pmo-1', u_zhang, tester, '周报已生成', 'TEXT', true, 'macos-merge-pmo', NOW() - INTERVAL '5 days')
  ON CONFLICT (id) DO NOTHING;

  -- ── 服务卡：给设计人设补可展示作品 ───────────────────────────────
  INSERT INTO "ServiceCard" (
    id, "userId", title, summary, description, "coverImage", category, "serviceType",
    "cityCode", "regionId", tags, "priceMin", "priceMax", "priceUnit",
    "deliveryMode", availability, status, "isPublic", "publishedAt", "createdAt", "updatedAt"
  ) VALUES
    ('macos-sc-chen-1', u_chen, '消费品牌 App 用户增长策略',
     '用户分层与关键路径优化',
     '通过用户分层与关键路径优化，推动 DAU 提升 35%，次日留存提升 12%。',
     '/uploads/card-covers/10001.jpg', '产品策略', 'ONLINE', '310000', 310000,
     ARRAY['产品策略', '用户研究', '数据分析'], 3000, 8000, '次',
     'ONLINE', 'AVAILABLE', 'PUBLISHED', true, NOW(), NOW(), NOW()),
    ('macos-sc-zhou-1', u_zhou, '工具类产品图标体系',
     '多尺寸导出与规范',
     '建立多尺寸导出规范，完成一次集中修改与交付。',
     '/uploads/card-covers/10002.jpg', '视觉设计', 'ONLINE', '330100', 330100,
     ARRAY['品牌升级', '图标设计'], 800, 2500, '套',
     'ONLINE', 'AVAILABLE', 'PUBLISHED', true, NOW(), NOW(), NOW()),
    ('macos-sc-linxia-1', linxia, '早期产品访谈验证',
     '提纲 · 执行 · 洞察',
     '完成提纲、执行与结构化洞察，支撑迭代方向。',
     '/uploads/card-covers/10008.jpg', '用户研究', 'ONLINE', '310000', 310000,
     ARRAY['用户研究', '用户访谈'], 1200, 4000, '次',
     'ONLINE', 'AVAILABLE', 'PUBLISHED', true, NOW(), NOW(), NOW()),
    ('macos-sc-chenshu-1', chenshu, '协作平台接口联调',
     '字段对齐与联调清单',
     '两周完成核心链路联调，附运维与交接清单。',
     '/uploads/card-covers/10003.jpg', '全栈开发', 'ONLINE', '110000', 110000,
     ARRAY['接口联调', '后端工程'], 2000, 6000, '次',
     'ONLINE', 'AVAILABLE', 'PUBLISHED', true, NOW(), NOW(), NOW()),
    ('macos-sc-xu-1', u_xu, '产品官网叙事重构',
     '卖点与案例结构',
     '统一卖点表达与案例结构，提升询盘转化。',
     '/uploads/card-covers/10006.jpg', '内容策略', 'ONLINE', '510100', 510100,
     ARRAY['内容策略', '文案'], 900, 2800, '次',
     'ONLINE', 'AVAILABLE', 'PUBLISHED', true, NOW(), NOW(), NOW())
  ON CONFLICT (id) DO NOTHING;

  -- ── 圈子：把测试账号拉进设计稿同名圈子 ───────────────────────────
  SELECT id INTO circle_id FROM "Circle" WHERE name = '独立产品人共创组' ORDER BY "createdAt" ASC LIMIT 1;
  IF circle_id IS NOT NULL THEN
    INSERT INTO "CircleMember" ("circleId", "userId", role, "joinedAt")
    VALUES (circle_id, tester, 'MEMBER', NOW() - INTERVAL '7 days')
    ON CONFLICT DO NOTHING;
    INSERT INTO "CircleMember" ("circleId", "userId", role, "joinedAt")
    VALUES
      (circle_id, linxia, 'MEMBER', NOW() - INTERVAL '10 days'),
      (circle_id, chenshu, 'MEMBER', NOW() - INTERVAL '10 days'),
      (circle_id, u_chen, 'MEMBER', NOW() - INTERVAL '10 days'),
      (circle_id, u_fang, 'MEMBER', NOW() - INTERVAL '9 days'),
      (circle_id, u_xu, 'MEMBER', NOW() - INTERVAL '9 days')
    ON CONFLICT DO NOTHING;
  END IF;

  SELECT id INTO circle_id FROM "Circle" WHERE name = 'UX 设计师互助圈' LIMIT 1;
  IF circle_id IS NOT NULL THEN
    INSERT INTO "CircleMember" ("circleId", "userId", role, "joinedAt")
    VALUES (circle_id, tester, 'MEMBER', NOW() - INTERVAL '5 days')
    ON CONFLICT DO NOTHING;
  END IF;

  SELECT id INTO circle_id FROM "Circle" WHERE name = 'AI 应用探索联盟' LIMIT 1;
  IF circle_id IS NOT NULL THEN
    INSERT INTO "CircleMember" ("circleId", "userId", role, "joinedAt")
    VALUES (circle_id, tester, 'MEMBER', NOW() - INTERVAL '4 days')
    ON CONFLICT DO NOTHING;
  END IF;

  -- 点数保底
  UPDATE "User" SET points = GREATEST(points, 1000000) WHERE id = tester;
END $$;
