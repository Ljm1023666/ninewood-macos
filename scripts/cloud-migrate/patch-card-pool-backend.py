#!/usr/bin/env python3
"""卡池后端：活池/死池列表契约、应标允许 ACTIVE、死池可抢单。"""
from pathlib import Path

ROOT = Path("/opt/ninewood/server/src")
pool_service = ROOT / "services" / "pool.service.ts"
bid_service = ROOT / "services" / "bid.service.ts"
demand_service = ROOT / "services" / "demand.service.ts"


MAPPER = r'''
function mapPoolListItem(d: any) {
  const applicantCount = Number(
    d.applicantCount ?? d._count?.applications ?? 0,
  );
  const amountEstimate =
    d.amountEstimate != null && d.amountEstimate !== ''
      ? Number(d.amountEstimate)
      : null;
  const expireAt =
    d.expireAt instanceof Date ? d.expireAt.toISOString() : d.expireAt;
  const visibleUntil =
    d.visibleUntil instanceof Date
      ? d.visibleUntil.toISOString()
      : d.visibleUntil;
  const description = d.description ? String(d.description) : '';
  return {
    id: d.id,
    title: d.title,
    tagName: d.tagName ?? null,
    minPrice: Number(d.minPrice),
    expectedPrice: amountEstimate,
    amountEstimate,
    category: d.category,
    taxonomyLeafId: d.taxonomyLeafId ?? null,
    serviceType: d.serviceType,
    cityCode: d.cityCode ?? null,
    applicantCount,
    maxApplicants: d.maxApplicants ?? 10,
    distance: null,
    distanceKm: null,
    isExample: d.isExample ?? false,
    user: d.user
      ? {
          id: d.user.id,
          nickname: d.user.nickname,
          avatarUrl: d.user.avatarUrl,
          coverUrl: d.user.coverUrl,
          demandCardCoverUrl: d.user.demandCardCoverUrl,
          certificationLevel: d.user.certificationLevel,
          creditScore: d.user.creditScore,
          completedOrders: d.user.completedOrders,
        }
      : undefined,
    mediaUrls: d.mediaUrls ?? [],
    coverImage: d.coverImage,
    coverUrl: d.coverImage,
    isSnatched: false,
    createdAt:
      d.createdAt instanceof Date ? d.createdAt.toISOString() : d.createdAt,
    status: d.status,
    stage: d.stage,
    visibilityWindow: d.visibilityWindow,
    expectedOutcome: d.expectedOutcome,
    expireAt,
    visibleUntil,
    deadlineAt: expireAt,
    tags: d.tags ?? [],
    acceptedProviderId: d.acceptedProviderId ?? null,
    deposit: d.deposit != null ? Number(d.deposit) : 0,
    lifecycleStage: d.lifecycleStage,
    isCertifiedOnly: d.isCertifiedOnly ?? false,
    descriptionPreview: description
      ? description.length > 160
        ? `${description.slice(0, 160)}…`
        : description
      : undefined,
  };
}

'''


def patch_pool_service() -> None:
    text = pool_service.read_text()
    if "function mapPoolListItem" not in text:
        text = text.replace(
            "export const poolService = {",
            MAPPER + "export const poolService = {",
        )

    old_active_where = """    const and: any[] = [
      { deletedAt: null },
    ];

    // Stage filter
    if (params.special) {
      and.push({ stage: { in: ['active', 'compressed'] } });
    } else {
      and.push({ stage: 'active' });
    }"""
    new_active_where = """    const and: any[] = [
      { deletedAt: null },
      // 活池不展示已过期（过期进死池）
      { expireAt: { gte: new Date() } },
    ];

    // Stage filter
    if (params.special) {
      and.push({ stage: { in: ['active', 'compressed'] } });
    } else {
      and.push({ stage: 'active' });
    }"""
    if "expireAt: { gte: new Date() }" not in text:
        if old_active_where not in text:
            raise SystemExit("getActive where block not found")
        text = text.replace(old_active_where, new_active_where)

    # getActive return
    old_active = """    return {
      demands,
      total,
      page,
      limit,
      totalPages: Math.max(1, Math.ceil(total / limit)),
      busyProviders: busyProviders.length > 0 ? busyProviders : undefined,
    };"""
    new_active = """    return {
      demands: demands.map((d: any) => mapPoolListItem(d)),
      total,
      page,
      limit,
      totalPages: Math.max(1, Math.ceil(total / limit)),
      busyProviders: busyProviders.length > 0 ? busyProviders : undefined,
    };"""
    if old_active not in text:
        raise SystemExit("getActive return block not found")
    text = text.replace(old_active, new_active)

    # Expand user select on getActive
    text = text.replace(
        """          user: {
            select: {
              id: true,
              nickname: true,
              avatarUrl: true,
              demandCardCoverUrl: true,
              certificationLevel: true,
            },
          },
          _count: { select: { applications: true } },
          activeDemand: true,""",
        """          user: {
            select: {
              id: true,
              nickname: true,
              avatarUrl: true,
              coverUrl: true,
              demandCardCoverUrl: true,
              certificationLevel: true,
              creditScore: true,
              completedOrders: true,
            },
          },
          _count: { select: { applications: true } },
          activeDemand: true,""",
        1,
    )

    # getDead: also allow expired ACTIVE/PENDING still in marketplace, OR stage completed
    # Keep stage=completed as primary; map list items
    old_dead_where = """    const and: any[] = [
      { stage: 'completed', deletedAt: null },
    ];"""
    new_dead_where = """    // 死池：已完成归档，或可见窗口/过期后仍可抢的 PENDING/ACTIVE
    const and: any[] = [
      { deletedAt: null },
      {
        OR: [
          { stage: 'completed' },
          {
            AND: [
              { stage: 'active' },
              { status: { in: ['PENDING', 'ACTIVE', 'FROZEN'] } },
              { expireAt: { lt: new Date() } },
            ],
          },
        ],
      },
    ];"""
    if old_dead_where not in text:
        raise SystemExit("getDead where block not found")
    text = text.replace(old_dead_where, new_dead_where)

    old_dead_return = """    return {
      demands,
      total,
      page,
      limit,
      totalPages: Math.max(1, Math.ceil(total / limit)),
    };
  },

  // ======== 时间杠杆（纯函数） ========"""
    new_dead_return = """    return {
      demands: demands.map((d: any) => mapPoolListItem(d)),
      total,
      page,
      limit,
      totalPages: Math.max(1, Math.ceil(total / limit)),
    };
  },

  // ======== 时间杠杆（纯函数） ========"""
    if old_dead_return not in text:
        raise SystemExit("getDead return block not found")
    text = text.replace(old_dead_return, new_dead_return)

    # Expand dead pool user select
    text = text.replace(
        """          user: {
            select: {
              id: true,
              nickname: true,
              avatarUrl: true,
              demandCardCoverUrl: true,
              certificationLevel: true,
            },
          },
          _count: { select: { applications: true } },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      prisma.demand.count({ where }),
    ]);

    return {
      demands: demands.map((d: any) => mapPoolListItem(d)),""",
        """          user: {
            select: {
              id: true,
              nickname: true,
              avatarUrl: true,
              coverUrl: true,
              demandCardCoverUrl: true,
              certificationLevel: true,
              creditScore: true,
              completedOrders: true,
            },
          },
          _count: { select: { applications: true } },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      prisma.demand.count({ where }),
    ]);

    return {
      demands: demands.map((d: any) => mapPoolListItem(d)),""",
        1,
    )

    pool_service.write_text(text)
    print("patched pool.service.ts")


def patch_bid() -> None:
    text = bid_service.read_text()
    old = """      if (demand.stage !== 'active') throw Object.assign(new Error('该需求不在应标阶段'), { status: 400 });
      if (demand.status !== 'PENDING') throw Object.assign(new Error('该需求不可应标'), { status: 400 });"""
    new = """      if (demand.stage !== 'active' && demand.stage !== 'compressed') {
        throw Object.assign(new Error('该需求不在应标阶段'), { status: 400 });
      }
      // 市场活池以 ACTIVE 为主；PENDING 为历史态，二者均可意向应标（不成单）
      if (demand.status !== 'PENDING' && demand.status !== 'ACTIVE') {
        throw Object.assign(new Error('该需求不可应标'), { status: 400 });
      }"""
    if old not in text:
        raise SystemExit("bid status check not found")
    text = text.replace(old, new)
    bid_service.write_text(text)
    print("patched bid.service.ts")


def patch_snatch() -> None:
    text = demand_service.read_text()
    old = """  async snatch( /** @deprecated 使用 requestDemand+acceptApplicant (V2) 替代 */demandId: string, userId: string) {
    const demand = await prisma.demand.findUnique({ where: { id: demandId } });
    if (!demand) throw { status: 404, message: '需求不存在' };
    if (demand.userId === userId) throw { status: 400, message: '不能抢自己的需求' };
    if (demand.isExample) throw { status: 400, message: '示例需求，仅供体验' };
    if (demand.status !== 'PENDING') throw { status: 400, message: '该需求不可抢单' };"""
    new = """  async snatch( /** @deprecated 使用 requestDemand+acceptApplicant (V2) 替代 */demandId: string, userId: string) {
    const demand = await prisma.demand.findUnique({ where: { id: demandId } });
    if (!demand) throw { status: 404, message: '需求不存在' };
    if (demand.userId === userId) throw { status: 400, message: '不能抢自己的需求' };
    if (demand.isExample) throw { status: 400, message: '示例需求，仅供体验' };
    // 死池抢单：stage=completed；或活池过期仍为 PENDING/ACTIVE
    const snatchable =
      demand.stage === 'completed' ||
      ((demand.status === 'PENDING' || demand.status === 'ACTIVE') &&
        demand.expireAt.getTime() < Date.now());
    if (!snatchable) throw { status: 400, message: '该需求不可抢单（仅死池/已过期）' };"""
    if old not in text:
        raise SystemExit("snatch status check not found")
    text = text.replace(old, new)
    demand_service.write_text(text)
    print("patched demand.service snatch")


def main() -> None:
    patch_pool_service()
    patch_bid()
    patch_snatch()


if __name__ == "__main__":
    main()
