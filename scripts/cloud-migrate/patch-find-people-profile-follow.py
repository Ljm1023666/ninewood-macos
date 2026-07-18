#!/usr/bin/env python3
"""找人：公开资料返回 isFollowing；可选鉴权。"""
from pathlib import Path

route = Path("/opt/ninewood/server/src/routes/user.ts")
service = Path("/opt/ninewood/server/src/services/user.service.ts")

rt = route.read_text()
if "optionalAuthMiddleware" not in rt:
    rt = rt.replace(
        "import { authMiddleware } from '../middleware/auth.js';",
        "import { authMiddleware, optionalAuthMiddleware } from '../middleware/auth.js';",
    )

old = """// GET /api/users/:id — 公开资料（不含手机号等 PII）
userRouter.get('/:id', async (req: Request, res: Response) => {
  try {
    const user = await userService.getPublicProfile(req.params.id as string);
    success(res, user);
  } catch (e: any) {
    fail(res, e.message || '服务器错误', e.status || 500);
  }
});"""

new = """// GET /api/users/:id — 公开资料（不含手机号等 PII）
userRouter.get('/:id', optionalAuthMiddleware, async (req: Request, res: Response) => {
  try {
    const user = await userService.getPublicProfile(
      req.params.id as string,
      (req as any).user?.userId,
    );
    success(res, user);
  } catch (e: any) {
    fail(res, e.message || '服务器错误', e.status || 500);
  }
});"""

if "getPublicProfile(\n      req.params.id" in rt or "viewerUserId" in rt and "get('/:id', optionalAuthMiddleware" in rt:
    print("user :id route already patched")
elif old not in rt:
    raise SystemExit("user :id route not found")
else:
    rt = rt.replace(old, new, 1)
    route.write_text(rt)
    print("patched user :id route")

sv = service.read_text()
old_fn = """  /** 公开资料：剥离手机号、邮箱、生日等 PII */
  async getPublicProfile(userId: string) {
    const cacheKey = `user:public:v1:${userId}`;
    const cached = await getCache<any>(cacheKey);
    if (cached) return cached;

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        nickname: true,
        avatarUrl: true,
        coverUrl: true,
        demandCardCoverUrl: true,
        certificationLevel: true,
        bio: true,
        creditScore: true,
        completedOrders: true,
      },
    });
    if (!user) throw { status: 404, message: '用户不存在' };

    await setCache(cacheKey, user, 300);
    return user;
  },"""

new_fn = """  /** 公开资料：剥离手机号、邮箱、生日等 PII */
  async getPublicProfile(userId: string, viewerUserId?: string) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        nickname: true,
        avatarUrl: true,
        coverUrl: true,
        demandCardCoverUrl: true,
        certificationLevel: true,
        bio: true,
        creditScore: true,
        completedOrders: true,
        cityCode: true,
        ipRegion: true,
        serviceTags: true,
      },
    });
    if (!user) throw { status: 404, message: '用户不存在' };

    let isFollowing: boolean | undefined;
    if (viewerUserId && viewerUserId !== userId) {
      const f = await prisma.follow.findUnique({
        where: {
          followerId_followingId: { followerId: viewerUserId, followingId: userId },
        },
        select: { followerId: true },
      });
      isFollowing = !!f;
    }

    return {
      ...user,
      isFollowing,
    };
  },"""

if "async getPublicProfile(userId: string, viewerUserId?: string)" in sv:
    print("getPublicProfile already patched")
elif old_fn not in sv:
    raise SystemExit("getPublicProfile not found")
else:
    service.write_text(sv.replace(old_fn, new_fn, 1))
    print("patched getPublicProfile")
