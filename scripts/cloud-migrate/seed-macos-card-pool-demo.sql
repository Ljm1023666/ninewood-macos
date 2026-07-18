-- macOS 卡池联调：活池应标样本 + 死池抢单样本
-- 发布者：13884283997；抢单/应标用户：19900001234（补 INTERMEDIATE + 抢单额度）

DO $$
DECLARE
  publisher TEXT := '29844721-ff7f-4340-b60d-d68a73c5d6c7';
  tester TEXT := 'a5122abf-6c88-4c76-a14a-6166c0c434db';
BEGIN
  -- 测试账号：中级认证 + 抢单额度，便于死池抢单
  UPDATE "User"
  SET "certificationLevel" = 'INTERMEDIATE',
      "snatchCredits" = GREATEST("snatchCredits", 5)
  WHERE id = tester;

  -- 活池应标样本（ACTIVE + 未过期）
  INSERT INTO "Demand" (
    id, "userId", title, description, "minPrice", category, "serviceType",
    "cityCode", "regionId", "isCertifiedOnly", stage, "coverImage", "amountEstimate",
    "expireAt", status, "mediaUrls", "applicantCount", "isExample", "isPublic",
    "visibilityWindow", "visibleUntil", "expectedOutcome", deposit, "maxApplicants",
    tags, "tagsConfirmed", "fuzzyLat", "fuzzyLng", "lifecycleStage", paths
  ) VALUES (
    'macos-pool-active-001',
    publisher,
    '卡池联调 · 产品图标统一优化',
    '需要把现有图标风格统一，输出多端尺寸与使用规范，适合卡池应标联调。',
    680,
    '视觉设计',
    'ONLINE',
    '310000',
    310000,
    false,
    'active',
    '/uploads/card-covers/10020.jpg',
    980,
    NOW() + INTERVAL '12 days',
    'ACTIVE',
    '[]'::jsonb,
    3,
    false,
    true,
    15,
    NOW() + INTERVAL '15 minutes',
    '统一风格图标包 + 导出规范 + 源文件',
    0,
    20,
    ARRAY['图标设计', '品牌升级', '卡池'],
    true,
    31.2304,
    121.4737,
    'ACTIVE',
    ARRAY['cat:视觉设计', 'attr:servicetype=online']
  )
  ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    status = 'ACTIVE',
    stage = 'active',
    "expireAt" = EXCLUDED."expireAt",
    "visibleUntil" = EXCLUDED."visibleUntil",
    "isPublic" = true;

  -- 死池样本 A：stage=completed（归档死池）
  INSERT INTO "Demand" (
    id, "userId", title, description, "minPrice", category, "serviceType",
    "cityCode", "regionId", "isCertifiedOnly", stage, "coverImage", "amountEstimate",
    "expireAt", status, "mediaUrls", "applicantCount", "isExample", "isPublic",
    "visibilityWindow", "visibleUntil", "expectedOutcome", deposit, "maxApplicants",
    tags, "tagsConfirmed", "fuzzyLat", "fuzzyLng", "lifecycleStage", paths
  ) VALUES (
    'macos-pool-dead-001',
    publisher,
    '死池联调 · 过期官网落地页设计',
    '原需求已过期未成交，进入死池。认证服务者可尝试抢单。',
    520,
    '界面设计',
    'ONLINE',
    '310000',
    310000,
    false,
    'completed',
    '/uploads/card-covers/10021.jpg',
    760,
    NOW() - INTERVAL '3 days',
    'COMPLETED',
    '[]'::jsonb,
    0,
    false,
    true,
    15,
    NOW() - INTERVAL '2 days',
    '高保真官网落地页与基础组件说明',
    0,
    10,
    ARRAY['官网', '落地页', '死池'],
    true,
    31.2244,
    121.4692,
    'ARCHIVED',
    ARRAY['cat:界面设计', 'attr:servicetype=online']
  )
  ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    stage = 'completed',
    status = 'COMPLETED',
    "expireAt" = EXCLUDED."expireAt",
    "visibleUntil" = EXCLUDED."visibleUntil",
    "isPublic" = true;

  -- 死池样本 B：active 但已过期（过期死池）
  INSERT INTO "Demand" (
    id, "userId", title, description, "minPrice", category, "serviceType",
    "cityCode", "regionId", "isCertifiedOnly", stage, "coverImage", "amountEstimate",
    "expireAt", status, "mediaUrls", "applicantCount", "isExample", "isPublic",
    "visibilityWindow", "visibleUntil", "expectedOutcome", deposit, "maxApplicants",
    tags, "tagsConfirmed", "fuzzyLat", "fuzzyLng", "lifecycleStage", paths
  ) VALUES (
    'macos-pool-dead-002',
    publisher,
    '死池联调 · 过期用户访谈招募',
    '可见窗口与截止时间已过，进入可抢单死池。',
    420,
    '用户研究',
    'OFFLINE',
    '310000',
    310000,
    false,
    'active',
    '/uploads/card-covers/10022.jpg',
    600,
    NOW() - INTERVAL '1 day',
    'ACTIVE',
    '[]'::jsonb,
    1,
    false,
    true,
    15,
    NOW() - INTERVAL '12 hours',
    '访谈招募名单与基础筛选说明',
    0,
    8,
    ARRAY['用户访谈', '招募', '死池'],
    true,
    31.2368,
    121.4801,
    'ACTIVE',
    ARRAY['cat:用户研究', 'attr:servicetype=offline', 'rgn:310000']
  )
  ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    stage = 'active',
    status = 'ACTIVE',
    "expireAt" = EXCLUDED."expireAt",
    "visibleUntil" = EXCLUDED."visibleUntil",
    "isPublic" = true;
END $$;
