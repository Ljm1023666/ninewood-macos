#!/usr/bin/env python3
"""找人后端：认证服务者列表对齐 SoftUserDTO；可选鉴权带回 isFollowing。"""
from pathlib import Path

ROOT = Path("/opt/ninewood/server/src")
cert_service = ROOT / "services" / "certification.service.ts"
cert_route = ROOT / "routes" / "certification.ts"
user_service = ROOT / "services" / "user.service.ts"


def patch_cert_service() -> None:
    text = cert_service.read_text()
    old = """  async search(params: {
    tags?: string[];
    regionId?: number;
    minRating?: number;
    maxRating?: number;
    page?: number;
    limit?: number;
  }) {
    const { tags, regionId, minRating, maxRating, page = 1, limit = 20 } = params;

    const where: any = {};

    if (tags && tags.length > 0) {
      where.tags = { hasSome: tags };
    }

    if (regionId !== undefined) {
      where.regionId = regionId;
    }

    if (minRating !== undefined || maxRating !== undefined) {
      where.avgRating = {
        ...(minRating !== undefined ? { gte: minRating } : {}),
        ...(maxRating !== undefined ? { lte: maxRating } : {}),
      };
    }

    const skip = (page - 1) * limit;

    const [rows, total] = await Promise.all([
      prisma.certifiedProvider.findMany({
        where,
        include: {
          user: {
            select: {
              id: true,
              nickname: true,
              avatarUrl: true,
              certificationLevel: true,
            },
          },
          region: { select: { id: true, name: true } },
        },
        orderBy: { avgRating: 'desc' },
        skip,
        take: limit,
      }),
      prisma.certifiedProvider.count({ where }),
    ]);

    // 扁平化为前端接口格式
    const items = rows.map((r) => ({
      id: r.user.id,
      nickname: r.user.nickname,
      avatarUrl: r.user.avatarUrl,
      certificationLevel: r.user.certificationLevel,
      tags: r.tags,
      avgRating: r.avgRating,
      totalCompleted: r.totalCompleted,
      region: r.region ? { id: r.region.id, name: r.region.name } : undefined,
    }));

    return { items, page, limit, total, totalPages: Math.ceil(total / limit) };
  },"""

    new = """  async search(params: {
    tags?: string[];
    regionId?: number;
    minRating?: number;
    maxRating?: number;
    page?: number;
    limit?: number;
    viewerUserId?: string;
  }) {
    const { tags, regionId, minRating, maxRating, page = 1, limit = 20, viewerUserId } = params;

    const where: any = {};

    if (tags && tags.length > 0) {
      where.tags = { hasSome: tags };
    }

    if (regionId !== undefined) {
      where.regionId = regionId;
    }

    if (minRating !== undefined || maxRating !== undefined) {
      where.avgRating = {
        ...(minRating !== undefined ? { gte: minRating } : {}),
        ...(maxRating !== undefined ? { lte: maxRating } : {}),
      };
    }

    const skip = (page - 1) * limit;

    const [rows, total] = await Promise.all([
      prisma.certifiedProvider.findMany({
        where,
        include: {
          user: {
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
          },
          region: { select: { id: true, name: true } },
        },
        orderBy: [{ avgRating: 'desc' }, { totalCompleted: 'desc' }],
        skip,
        take: limit,
      }),
      prisma.certifiedProvider.count({ where }),
    ]);

    let followingSet = new Set<string>();
    if (viewerUserId && rows.length > 0) {
      const ids = rows.map((r) => r.user.id);
      const follows = await prisma.follow.findMany({
        where: { followerId: viewerUserId, followingId: { in: ids } },
        select: { followingId: true },
      });
      followingSet = new Set(follows.map((f) => f.followingId));
    }

    // SoftUserDTO 兼容：macOS 找人页 / 认证检索
    const items = rows.map((r) => ({
      id: r.user.id,
      nickname: r.user.nickname,
      avatarUrl: r.user.avatarUrl,
      coverUrl: r.user.coverUrl,
      demandCardCoverUrl: r.user.demandCardCoverUrl,
      certificationLevel: r.user.certificationLevel,
      bio: r.user.bio,
      creditScore: r.user.creditScore,
      completedOrders: r.user.completedOrders ?? r.totalCompleted,
      cityCode: r.user.cityCode,
      ipRegion: r.region?.name ?? r.user.ipRegion,
      isFollowing: viewerUserId ? followingSet.has(r.user.id) : undefined,
      tags: r.tags?.length ? r.tags : r.user.serviceTags,
      avgRating: r.avgRating,
      totalCompleted: r.totalCompleted,
      region: r.region ? { id: r.region.id, name: r.region.name } : undefined,
    }));

    return {
      items,
      users: items,
      page,
      limit,
      total,
      totalPages: Math.max(1, Math.ceil(total / limit)),
    };
  },"""

    if "viewerUserId?: string" in text and "SoftUserDTO 兼容" in text:
        print("cert search already patched")
    elif old not in text:
        raise SystemExit("cert search block not found")
    else:
        text = text.replace(old, new, 1)
        cert_service.write_text(text)
        print("patched certification.service search")


def patch_cert_route() -> None:
    text = cert_route.read_text()
    if "optionalAuthMiddleware" not in text:
        text = text.replace(
            "import { authMiddleware } from '../middleware/auth.js';",
            "import { authMiddleware, optionalAuthMiddleware } from '../middleware/auth.js';",
        )
    text = text.replace(
        "certificationRouter.get('/providers', async (req: Request, res: Response) => {",
        "certificationRouter.get('/providers', optionalAuthMiddleware, async (req: Request, res: Response) => {",
    )
    old_call = """    const result = await certificationService.search({
      tags,
      regionId: params.regionId,
      minRating: params.minRating,
      maxRating: params.maxRating,
      page: params.page,
      limit: params.limit,
    });
    paginated(res, result.items, result.page, result.limit, result.total);"""
    new_call = """    const result = await certificationService.search({
      tags,
      regionId: params.regionId,
      minRating: params.minRating,
      maxRating: params.maxRating,
      page: params.page,
      limit: params.limit,
      viewerUserId: (req as any).user?.userId,
    });
    // 同时返回 items/users，兼容 SoftUserDTO 数组与 UserListPage
    success(res, {
      items: result.items,
      users: result.users ?? result.items,
      page: result.page,
      limit: result.limit,
      total: result.total,
      totalPages: result.totalPages,
    });"""
    if "viewerUserId: (req as any).user?.userId" in text:
        print("cert route already patched")
    elif old_call not in text:
        raise SystemExit("cert providers call not found")
    else:
        if "import { success, fail, paginated }" in text and "success(res, {" in new_call:
            # success already imported
            pass
        text = text.replace(old_call, new_call, 1)
        cert_route.write_text(text)
        print("patched certification providers route")


def patch_user_search() -> None:
    text = user_service.read_text()
    old = """      select: {
        id: true, nickname: true, avatarUrl: true, certificationLevel: true, bio: true,
      },
      take: limit,
      orderBy: { certificationLevel: 'desc' },
    });
    return users;
  },"""
    new = """      select: {
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
      },
      take: limit,
      orderBy: { certificationLevel: 'desc' },
    });
    return users;
  },"""
    if "creditScore: true" in text[text.find("async searchUsers"): text.find("async searchUsers") + 800]:
        print("searchUsers already rich")
        return
    if old not in text:
        raise SystemExit("searchUsers select block not found")
    user_service.write_text(text.replace(old, new, 1))
    print("patched searchUsers SoftUserDTO fields")


def main() -> None:
    patch_cert_service()
    patch_cert_route()
    patch_user_search()


if __name__ == "__main__":
    main()
