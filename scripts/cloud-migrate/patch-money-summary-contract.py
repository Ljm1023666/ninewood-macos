#!/usr/bin/env python3
"""Patch production money summary on demand create + order list/detail; fix prepay deposit."""
from pathlib import Path

MONEY_HELPER = '''
const MONEY_RULE_VERSION = '2026-07'

/** 与 pay-breakdown / BR-001 对齐的机器可读资金摘要 */
export function buildMoneySummary(opts: {
  minPrice: number
  deposit: number
  agreedPrice?: number
  isPublicWelfare?: boolean
  alreadyPrepaid?: boolean
}) {
  const minimumPrice = Number(opts.minPrice) || 0
  const depositRequired = Number(opts.deposit ?? minimumPrice) || 0
  const agreed = opts.agreedPrice != null ? Number(opts.agreedPrice) : minimumPrice
  const serviceFeeRate = opts.isPublicWelfare ? 0.1 : 0.05
  const serviceFee = Math.round(agreed * serviceFeeRate * 100) / 100
  return {
    currency: 'POINT' as const,
    ruleVersion: MONEY_RULE_VERSION,
    minimumPrice,
    depositRequired,
    escrowRequired: depositRequired,
    escrowAmount: depositRequired,
    serviceFeeRate,
    serviceFee,
    remainingPay: Math.max(0, agreed - depositRequired),
    payableNow: opts.alreadyPrepaid ? 0 : serviceFee,
  }
}
'''

# --- settlement.ts: append helper if missing ---
settlement = Path('/opt/ninewood/server/src/services/settlement.ts')
stext = settlement.read_text()
if 'buildMoneySummary' not in stext:
    settlement.write_text(stext.rstrip() + '\n' + MONEY_HELPER + '\n')
    print('settlement.ts: added buildMoneySummary')
else:
    print('settlement.ts: buildMoneySummary already present')

# --- demand.service.ts: enrich create return ---
demand = Path('/opt/ninewood/server/src/services/demand.service.ts')
dtext = demand.read_text()
if "buildMoneySummary" not in dtext:
    # add import
    if "from './settlement.js'" in dtext:
        dtext = dtext.replace(
            "from './settlement.js'",
            "from './settlement.js';\nimport { buildMoneySummary } from './settlement.js'",
            1,
        )
    else:
        # find a good import spot after wallet
        needle = "import { checkFrozenBeforePublish } from './deposit-new.js'"
        if needle not in dtext:
            raise SystemExit('demand.service import anchor missing')
        dtext = dtext.replace(
            needle,
            needle + "\nimport { buildMoneySummary } from './settlement.js'",
            1,
        )

old_return_tail = """    shadowOnDemandCreated({
      id: demand.id,
      userId: demand.userId,
      title: demand.title,
      paths: demand.paths,
    }).catch((err) => {
      console.error('[loop-shadow] demand created hook failed', demand.id, err);
    });

    return demand;
  },
"""
new_return_tail = """    shadowOnDemandCreated({
      id: demand.id,
      userId: demand.userId,
      title: demand.title,
      paths: demand.paths,
    }).catch((err) => {
      console.error('[loop-shadow] demand created hook failed', demand.id, err);
    });

    const money = buildMoneySummary({
      minPrice: Number(demand.minPrice),
      deposit: Number(demand.deposit),
      agreedPrice: Number(demand.minPrice),
    });
    return {
      ...demand,
      minPrice: Number(demand.minPrice),
      deposit: Number(demand.deposit),
      ...money,
    };
  },
"""
if old_return_tail not in dtext:
    raise SystemExit('demand create return block not found')
dtext = dtext.replace(old_return_tail, new_return_tail, 1)
demand.write_text(dtext)
print('demand.service.ts: create money summary')

# --- order.service.ts ---
order = Path('/opt/ninewood/server/src/services/order.service.ts')
otext = order.read_text()
if 'buildMoneySummary' not in otext:
    otext = otext.replace(
        "import { calculateSettlement } from './settlement.js';",
        "import { calculateSettlement, buildMoneySummary } from './settlement.js';",
        1,
    )

old_get = """    return {
      ...order,
      agreedPrice: Number(order.agreedPrice),
      demand: order.demand ? { ...order.demand, minPrice: Number(order.demand.minPrice), deposit: Number((order.demand as any).deposit ?? order.demand.minPrice) } : null,
    };
  },
"""
new_get = """    const minPrice = Number(order.demand?.minPrice ?? 0);
    const deposit = Number((order.demand as any)?.deposit ?? minPrice);
    const money = buildMoneySummary({
      minPrice,
      deposit,
      agreedPrice: Number(order.agreedPrice),
      alreadyPrepaid: Boolean(order.paidAt),
    });
    return {
      ...order,
      agreedPrice: Number(order.agreedPrice),
      demand: order.demand
        ? {
            ...order.demand,
            minPrice,
            deposit,
          }
        : null,
      ...money,
      escrowAmount: money.escrowAmount,
      remainingPay: money.remainingPay,
      serviceFee: money.serviceFee,
    };
  },
"""
if old_get not in otext:
    raise SystemExit('order getById return not found')
otext = otext.replace(old_get, new_get, 1)

old_list = """    const [orders, total] = await Promise.all([
      prisma.order.findMany({
        where,
        include: {
          provider: { select: { id: true, nickname: true, avatarUrl: true } },
          requester: { select: { id: true, nickname: true, avatarUrl: true } },
          demand: { select: { id: true, title: true, category: true } },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      prisma.order.count({ where }),
    ]);
    return {
      orders: orders.map((o: any) => ({ ...o, agreedPrice: Number(o.agreedPrice) })),
      total, page, totalPages: Math.ceil(total / limit),
    };
  },
"""
new_list = """    const [orders, total] = await Promise.all([
      prisma.order.findMany({
        where,
        include: {
          provider: { select: { id: true, nickname: true, avatarUrl: true } },
          requester: { select: { id: true, nickname: true, avatarUrl: true } },
          demand: {
            select: {
              id: true,
              title: true,
              category: true,
              minPrice: true,
              deposit: true,
              isPublicWelfare: true,
            },
          },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      prisma.order.count({ where }),
    ]);
    return {
      orders: orders.map((o: any) => {
        const minPrice = Number(o.demand?.minPrice ?? 0);
        const deposit = Number(o.demand?.deposit ?? minPrice);
        const money = buildMoneySummary({
          minPrice,
          deposit,
          agreedPrice: Number(o.agreedPrice),
          isPublicWelfare: Boolean(o.demand?.isPublicWelfare),
          alreadyPrepaid: Boolean(o.paidAt),
        });
        return {
          ...o,
          agreedPrice: Number(o.agreedPrice),
          demand: o.demand
            ? { ...o.demand, minPrice, deposit }
            : null,
          ...money,
          escrowAmount: money.escrowAmount,
          remainingPay: money.remainingPay,
          serviceFee: money.serviceFee,
        };
      }),
      total, page, totalPages: Math.ceil(total / limit),
    };
  },
"""
if old_list not in otext:
    raise SystemExit('order listMine block not found')
otext = otext.replace(old_list, new_list, 1)

old_prepay = """    const breakdown = calculateSettlement(
      Number(demand.minPrice),
      Number(order.agreedPrice),
      Number(demand.minPrice),
    )
"""
new_prepay = """    const deposit = Number((demand as any).deposit ?? demand.minPrice)
    const breakdown = calculateSettlement(
      Number(demand.minPrice),
      Number(order.agreedPrice),
      deposit,
    )
"""
if old_prepay not in otext:
    raise SystemExit('prepay calculateSettlement block not found')
otext = otext.replace(old_prepay, new_prepay, 1)

order.write_text(otext)
print('order.service.ts: list/detail money + prepay deposit')
print('OK')
