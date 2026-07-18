import { prisma } from '../lib/prisma.js';
import { assertUserContentSafe } from './content-filter/index.js';
import { userBlockService } from './user-block.service.js';

function dedupeMergeTimeline(messages: any[], viewerId: string) {
  const seenOwn = new Set<string>();
  const result: any[] = [];
  for (const msg of messages) {
    if (msg.fromUserId === viewerId) {
      const bucket = `${msg.fromUserId}|${msg.content}|${new Date(msg.createdAt).toISOString().slice(0, 19)}`;
      if (seenOwn.has(bucket)) continue;
      seenOwn.add(bucket);
      result.push(msg);
      continue;
    }
    if (msg.toUserId === viewerId) {
      result.push(msg);
    }
  }
  return result;
}

function notificationTitle(content: string) {
  const line = (content || '').split('\n').map((s) => s.trim()).find(Boolean);
  return line ? line.slice(0, 80) : '系统通知';
}

export const messageService = {
  async send(fromUserId: string, toUserId: string, content: string, orderId?: string, type = 'TEXT', duration?: number) {
    if (await userBlockService.isBlockedEitherWay(fromUserId, toUserId)) {
      throw Object.assign(new Error('无法向该用户发送消息'), { status: 403 });
    }
    if (type === 'TEXT') {
      assertUserContentSafe(content, '消息');
    }
    return prisma.message.create({
      data: { fromUserId, toUserId, content, type: type as any, orderId: orderId || null, duration: duration ?? null },
      include: {
        fromUser: { select: { id: true, nickname: true, avatarUrl: true } },
        toUser: { select: { id: true, nickname: true, avatarUrl: true } },
        cardAttachment: true,
      },
    });
  },

  async getConversations(userId: string) {
    const blockedIds = await userBlockService.getBlockedPartnerIds(userId);
    const messages = await prisma.message.findMany({
      where: {
        mergeId: null,
        OR: [{ fromUserId: userId }, { toUserId: userId }],
      },
      orderBy: { createdAt: 'desc' },
      take: 500,
      include: {
        fromUser: { select: { id: true, nickname: true, avatarUrl: true } },
        toUser: { select: { id: true, nickname: true, avatarUrl: true } },
        cardAttachment: true,
      },
    });

    const partnerIds: string[] = [];
    const conversations: any[] = [];
    const seen = new Set<string>();

    for (const msg of messages) {
      const otherId = msg.fromUserId === userId ? msg.toUserId : msg.fromUserId;
      if (otherId === userId || seen.has(otherId) || blockedIds.has(otherId)) continue;
      seen.add(otherId);
      partnerIds.push(otherId);
      const other = msg.fromUserId === userId ? msg.toUser : msg.fromUser;
      conversations.push({ user: other, lastMessage: msg, unreadCount: 0 });
    }

    if (partnerIds.length > 0) {
      const [unreadGroups, activeCommunications] = await Promise.all([
        prisma.message.groupBy({
          by: ['fromUserId'],
          where: {
            mergeId: null,
            toUserId: userId,
            isRead: false,
            fromUserId: { in: partnerIds },
          },
          _count: { _all: true },
        }),
        prisma.demandApplicantV2.findMany({
          where: {
            status: 'COMMUNICATING',
            OR: [{ userId }, { demand: { userId } }],
          },
          include: {
            demand: { select: { id: true, title: true, userId: true } },
          },
          orderBy: { commDeadline: 'desc' },
        }),
      ]);
      const unreadMap = new Map(unreadGroups.map((g) => [g.fromUserId, g._count._all]));
      const commMap = new Map<string, any>();
      for (const app of activeCommunications) {
        const partnerId = app.userId === userId ? app.demand.userId : app.userId;
        if (!commMap.has(partnerId)) {
          commMap.set(partnerId, {
            applicantId: app.id,
            demandId: app.demandId,
            demandTitle: app.demand.title,
            status: app.status,
            commStartAt: app.commStartAt,
            commDeadline: app.commDeadline,
            extensionMinutes: app.extensionMinutes,
            canExtend: app.demand.userId === userId,
          });
        }
      }
      for (const c of conversations) {
        c.unreadCount = unreadMap.get(c.user.id) || 0;
        c.communication = commMap.get(c.user.id) || null;
      }
    }

    return conversations;
  },

  async getMessages(userId: string, otherId: string, page = 1) {
    if (await userBlockService.isBlockedEitherWay(userId, otherId)) {
      throw Object.assign(new Error('无法查看与该用户的会话'), { status: 403 });
    }
    const limit = 50;
    const messages = await prisma.message.findMany({
      where: {
        mergeId: null,
        OR: [
          { fromUserId: userId, toUserId: otherId },
          { fromUserId: otherId, toUserId: userId },
        ],
      },
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * limit,
      take: limit,
      include: {
        fromUser: { select: { id: true, nickname: true, avatarUrl: true } },
        toUser: { select: { id: true, nickname: true, avatarUrl: true } },
        cardAttachment: true,
      },
    });

    await prisma.message.updateMany({
      where: { mergeId: null, fromUserId: otherId, toUserId: userId, isRead: false },
      data: { isRead: true },
    });

    return messages.reverse();
  },

  async getUnreadCount(userId: string) {
    return prisma.message.count({
      where: { toUserId: userId, isRead: false },
    });
  },

  async createMerge(userId: string, title: string, memberIds: string[]) {
    if (!title.trim()) throw { status: 400, message: '群聊名称不能为空' };
    assertUserContentSafe(title.trim(), '群聊名称');
    if (memberIds.length < 1) throw { status: 400, message: '至少选择一位联系人' };
    const ids = [...new Set([userId, ...memberIds])];
    return prisma.conversationMerge.create({
      data: {
        userId,
        title: title.trim(),
        members: { create: ids.map((id) => ({ userId: id })) },
      },
      include: { members: true },
    });
  },

  async getMerges(userId: string) {
    return prisma.conversationMerge.findMany({
      where: { members: { some: { userId } } },
      orderBy: { createdAt: 'desc' },
      include: { members: true },
    });
  },

  async getMergeMessages(mergeId: string, userId: string, page = 1) {
    const merge = await prisma.conversationMerge.findUnique({
      where: { id: mergeId },
      include: { members: true },
    });
    if (!merge) throw { status: 404, message: '群聊不存在' };
    if (!merge.members.some((m: any) => m.userId === userId)) {
      throw { status: 403, message: '不是群成员' };
    }

    const limit = 50;
    const messages = await prisma.message.findMany({
      where: { mergeId },
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * limit,
      take: limit,
      include: {
        fromUser: { select: { id: true, nickname: true, avatarUrl: true } },
        toUser: { select: { id: true, nickname: true, avatarUrl: true } },
        cardAttachment: true,
      },
    });
    return dedupeMergeTimeline(messages.reverse(), userId);
  },

  async sendMergeMessage(fromUserId: string, mergeId: string, content: string) {
    assertUserContentSafe(content, '消息');
    const merge = await prisma.conversationMerge.findUnique({
      where: { id: mergeId },
      include: { members: true },
    });
    if (!merge) throw { status: 404, message: '群聊不存在' };
    if (!merge.members.some((m: any) => m.userId === fromUserId)) {
      throw { status: 403, message: '不是群成员' };
    }

    const recipients = merge.members
      .map((m: any) => m.userId)
      .filter((id: string) => id !== fromUserId);

    for (const toId of recipients) {
      if (await userBlockService.isBlockedEitherWay(fromUserId, toId)) {
        throw Object.assign(new Error('无法向部分群成员发送消息'), { status: 403 });
      }
    }

    const msgs = await Promise.all(
      recipients.map((toId: string) =>
        prisma.message.create({
          data: { fromUserId, toUserId: toId, content, type: 'TEXT', mergeId },
          include: {
            fromUser: { select: { id: true, nickname: true, avatarUrl: true } },
            toUser: { select: { id: true, nickname: true, avatarUrl: true } },
            cardAttachment: true,
          },
        }),
      ),
    );
    return { messages: msgs, mergeId };
  },

  async markNotificationRead(userId: string, messageId: string) {
    const result = await prisma.message.updateMany({
      where: { id: messageId, toUserId: userId, type: 'SYSTEM' },
      data: { isRead: true },
    });
    if (result.count === 0) throw { status: 404, message: '通知不存在' };
    return { ok: true };
  },

  async markAllNotificationsRead(userId: string) {
    const result = await prisma.message.updateMany({
      where: { toUserId: userId, type: 'SYSTEM', isRead: false },
      data: { isRead: true },
    });
    return { ok: true, count: result.count };
  },

  async getNotifications(userId: string, page = 1) {
    const limit = 20;
    const [items, total] = await Promise.all([
      prisma.message.findMany({
        where: { toUserId: userId, type: 'SYSTEM' },
        include: { fromUser: { select: { id: true, nickname: true, avatarUrl: true } } },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      prisma.message.count({ where: { toUserId: userId, type: 'SYSTEM' } }),
    ]);
    return {
      items: items.map((item) => ({
        ...item,
        title: notificationTitle(item.content),
        type: item.type ?? 'SYSTEM',
      })),
      total,
      page,
      totalPages: Math.ceil(total / limit),
    };
  },
};
