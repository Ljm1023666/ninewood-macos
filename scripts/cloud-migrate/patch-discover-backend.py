#!/usr/bin/env python3
"""发现页后端：可选鉴权 + 列表契约字段 + 收藏分页兼容 macOS。"""
from pathlib import Path
import re

ROOT = Path("/opt/ninewood/server/src")
demand_route = ROOT / "routes" / "demand.ts"
demand_service = ROOT / "services" / "demand.service.ts"
user_service = ROOT / "services" / "user.service.ts"


def patch_demand_routes() -> None:
    text = demand_route.read_text()
    if "optionalAuthMiddleware" not in text:
        text = text.replace(
            "import { authMiddleware } from '../middleware/auth.js';",
            "import { authMiddleware, optionalAuthMiddleware } from '../middleware/auth.js';",
        )

    text = text.replace(
        "demandRouter.get('/search', async (req: Request, res: Response) => {",
        "demandRouter.get('/search', optionalAuthMiddleware, async (req: Request, res: Response) => {",
    )
    text = text.replace(
        "demandRouter.get('/:id', async (req: Request, res: Response) => {",
        "demandRouter.get('/:id', optionalAuthMiddleware, async (req: Request, res: Response) => {",
    )
    demand_route.write_text(text)
    print("patched demand routes (optionalAuth on search + detail)")


def patch_search_mapper() -> None:
    text = demand_service.read_text()

    helper = """
function mapSearchListItem(d: any, applicantCount: number, distance: number | null = null) {
  const amountEstimate =
    d.amountEstimate != null && d.amountEstimate !== ''
      ? Number(d.amountEstimate)
      : null;
  const expireAt = d.expireAt instanceof Date ? d.expireAt.toISOString() : d.expireAt;
  const visibleUntil =
    d.visibleUntil instanceof Date ? d.visibleUntil.toISOString() : d.visibleUntil;
  const user = d.user
    ? {
        id: d.user.id ?? d.userId,
        nickname: d.user.nickname,
        avatarUrl: d.user.avatarUrl,
        coverUrl: d.user.coverUrl,
        demandCardCoverUrl: d.user.demandCardCoverUrl,
        certificationLevel: d.user.certificationLevel,
        creditScore: d.user.creditScore ?? undefined,
        completedOrders: d.user.completedOrders ?? undefined,
        ipRegion: d.user.ipRegion ?? undefined,
      }
    : {
        id: d.userId,
        nickname: d.nickname,
        avatarUrl: d.avatarUrl,
        coverUrl: d.coverUrl,
        demandCardCoverUrl: d.demandCardCoverUrl,
        certificationLevel: d.certificationLevel,
      };

  return {
    id: d.id,
    title: d.title,
    tagName: d.tagName ?? null,
    minPrice: Number(d.minPrice),
    expectedPrice: amountEstimate,
    amountEstimate,
    category: d.category,
    taxonomyLeafId: d.taxonomyLeafId,
    serviceType: d.serviceType,
    cityCode: d.cityCode,
    applicantCount,
    maxApplicants: d.maxApplicants ?? 10,
    distance,
    distanceKm: distance,
    createdAgo: formatCreatedAgo(d.createdAt instanceof Date ? d.createdAt : new Date(d.createdAt)),
    isExample: d.isExample,
    user,
    mediaUrls: d.mediaUrls ?? [],
    coverImage: d.coverImage,
    coverUrl: d.coverImage,
    isSnatched: false,
    createdAt: d.createdAt instanceof Date ? d.createdAt.toISOString() : d.createdAt,
    status: d.status,
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
    descriptionPreview:
      d.description && String(d.description).length > 0
        ? String(d.description).length > 160
          ? `${String(d.description).slice(0, 160)}…`
          : String(d.description)
        : undefined,
  };
}

"""

    if "function mapSearchListItem" not in text:
        text = text.replace(
            "function formatCreatedAgo(createdAt: Date): string {",
            helper + "function formatCreatedAgo(createdAt: Date): string {",
        )

    # Geo path mapper
    text = re.sub(
        r"const result = raw\.map\(\(d: any\) => \(\{[\s\S]*?\}\)\);",
        """const result = raw.map((d: any) =>
        mapSearchListItem(
          d,
          Number(d.applicantCount ?? 0),
          d.distanceKm ? Math.round(Number(d.distanceKm) * 10) / 10 : null,
        ),
      );""",
        text,
        count=1,
    )

    # Non-geo path mapper
    text = re.sub(
        r"const paged = demands[\s\S]*?descriptionPreview:[\s\S]*?\}\)\);",
        """const paged = demands
      .filter((d: any) =>
        isVisibleInMarketplace({
          status: d.status,
          applicantCount: d.applicantCount ?? d._count?.applications ?? 0,
          maxApplicants: d.maxApplicants,
        }),
      )
      .map((d: any) =>
        mapSearchListItem(
          d,
          d.applicantCount ?? d._count?.applications ?? 0,
          null,
        ),
      );""",
        text,
        count=1,
    )

    # Detail: expose applicant to current viewer + hasRequested
    if "hasRequested:" not in text:
        text = text.replace(
            "const isOwner = userId === demand.userId;",
            "const isOwner = userId === demand.userId;\n"
            "    const myApplicant = userId\n"
            "      ? demand.applicantsV2.find((a: any) => a.userId === userId)\n"
            "      : undefined;\n"
            "    const hasRequested = !!myApplicant;",
        )
        text = text.replace(
            "applicantsV2: isOwner ? demand.applicantsV2 : demand.applicantsV2.filter(\n"
            "        (a: any) => a.userId === userId,\n"
            "      ),",
            "applicantsV2: isOwner\n"
            "        ? demand.applicantsV2\n"
            "        : myApplicant\n"
            "          ? [myApplicant]\n"
            "          : [],",
        )
        text = text.replace(
            "hasOrder,",
            "hasOrder,\n      hasRequested,",
        )

    # Include creditScore on list user select
    text = text.replace(
        "certificationLevel: true,\n          },\n        },\n        _count: { select: { applications: true } },",
        "certificationLevel: true,\n            creditScore: true,\n            completedOrders: true,\n            ipRegion: true,\n          },\n        },\n        _count: { select: { applications: true } },",
        1,
    )

    demand_service.write_text(text)
    print("patched demand.service search mapper + detail hasRequested")


def patch_favorites() -> None:
    text = user_service.read_text()
    old = """    return {
      list: list.map((f: any) => f.demand),
      total,
      page,
      totalPages: Math.ceil(total / limit),
    };"""

    new = """    const demands = list.map((f: any) => {
      const d = f.demand;
      const amountEstimate =
        d.amountEstimate != null && d.amountEstimate !== ''
          ? Number(d.amountEstimate)
          : null;
      const expireAt = d.expireAt instanceof Date ? d.expireAt.toISOString() : d.expireAt;
      return {
        id: d.id,
        title: d.title,
        minPrice: Number(d.minPrice),
        expectedPrice: amountEstimate,
        amountEstimate,
        category: d.category,
        serviceType: d.serviceType,
        mediaUrls: d.mediaUrls ?? [],
        coverImage: d.coverImage,
        coverUrl: d.coverImage,
        status: d.status,
        createdAt: d.createdAt instanceof Date ? d.createdAt.toISOString() : d.createdAt,
        expireAt,
        visibleUntil: d.visibleUntil instanceof Date ? d.visibleUntil.toISOString() : d.visibleUntil,
        deadlineAt: expireAt,
        user: d.user,
        applicantCount: d.applicantCount ?? 0,
        maxApplicants: d.maxApplicants ?? 10,
        tags: d.tags ?? [],
        deposit: d.deposit != null ? Number(d.deposit) : 0,
        lifecycleStage: d.lifecycleStage ?? 'ACTIVE',
        expectedOutcome: d.expectedOutcome ?? null,
        descriptionPreview: d.description
          ? d.description.length > 160
            ? `${d.description.slice(0, 160)}…`
            : d.description
          : undefined,
      };
    });
    return {
      demands,
      list: demands,
      total,
      page,
      limit,
      totalPages: Math.max(1, Math.ceil(total / limit)),
    };"""

    if old not in text:
        raise SystemExit("getFavorites return block not found")
    text = text.replace(old, new)

    old_select = """            select: {
              id: true, title: true, minPrice: true, category: true,
              serviceType: true, mediaUrls: true, status: true,
              createdAt: true,
              user: { select: { id: true, nickname: true, avatarUrl: true } },
            },"""

    new_select = """            select: {
              id: true, title: true, description: true, minPrice: true, category: true,
              serviceType: true, mediaUrls: true, status: true, coverImage: true,
              amountEstimate: true, expireAt: true, visibleUntil: true,
              applicantCount: true, maxApplicants: true, tags: true, deposit: true,
              lifecycleStage: true, expectedOutcome: true, createdAt: true,
              user: {
                select: {
                  id: true, nickname: true, avatarUrl: true, coverUrl: true,
                  demandCardCoverUrl: true, certificationLevel: true, creditScore: true,
                },
              },
            },"""

    text = text.replace(old_select, new_select)
    user_service.write_text(text)
    print("patched user.service getFavorites")


def main() -> None:
    patch_demand_routes()
    patch_search_mapper()
    patch_favorites()


if __name__ == "__main__":
    main()
