-- macOS 聊天联调样本：19900001234 ↔ 13884283997 + 一个群聊

DO $$
DECLARE
  u_a TEXT := 'a5122abf-6c88-4c76-a14a-6166c0c434db';
  u_b TEXT := '29844721-ff7f-4340-b60d-d68a73c5d6c7';
  merge_id TEXT := 'macos-demo-merge-001';
BEGIN
  INSERT INTO "Message" (id, "fromUserId", "toUserId", content, type, "isRead", "createdAt")
  VALUES
    ('macos-demo-msg-1', u_b, u_a, '你好，我在九木上看到你的需求，想进一步沟通一下。', 'TEXT', false, NOW() - INTERVAL '2 hours'),
    ('macos-demo-msg-2', u_a, u_b, '你好！可以的，请说说具体想了解哪些方面？', 'TEXT', true, NOW() - INTERVAL '115 minutes'),
    ('macos-demo-msg-3', u_b, u_a, '主要是用户访谈的样本量和交付周期。', 'TEXT', false, NOW() - INTERVAL '90 minutes'),
    ('macos-demo-msg-4', u_a, u_b, '样本 8-12 人、周期 5 个工作日左右，我可以发一张服务卡给你。', 'TEXT', true, NOW() - INTERVAL '60 minutes'),
    ('macos-demo-msg-5', u_b, u_a, '好的，我看看服务卡，稍后给你反馈。', 'TEXT', false, NOW() - INTERVAL '30 minutes')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO "ConversationMerge" (id, "userId", title, "createdAt")
  VALUES (merge_id, u_a, 'macOS 联调群', NOW())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO "ConversationMergeMember" ("mergeId", "userId")
  VALUES
    (merge_id, u_a),
    (merge_id, u_b)
  ON CONFLICT DO NOTHING;

  INSERT INTO "Message" (id, "fromUserId", "toUserId", content, type, "isRead", "mergeId", "createdAt")
  VALUES
    ('macos-demo-merge-1', u_b, u_a, '群聊联调：我把框架图更新到共享文件了。', 'TEXT', false, merge_id, NOW() - INTERVAL '20 minutes'),
    ('macos-demo-merge-2', u_a, u_b, '收到，我这边 macOS 客户端正在验证实时消息。', 'TEXT', true, merge_id, NOW() - INTERVAL '15 minutes')
  ON CONFLICT (id) DO NOTHING;
END $$;
