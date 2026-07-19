#!/usr/bin/env node
/**
 * community-seed-v1 — 给全部账号补齐「回」社区最低足迹（幂等）
 *
 * 用法（在 /opt/ninewood/server）:
 *   node scripts/seed-community-loop-v1.mjs --dry-run
 *   node scripts/seed-community-loop-v1.mjs --limit 80
 *   node scripts/seed-community-loop-v1.mjs
 *
 * 标记: community-seed-v1（Ledger.referenceType / Message.content 前缀 /
 *       ServiceCard.title 前缀 / LoopRun.correlationId / Circle.name 前缀）
 */
import { PrismaClient } from '@prisma/client'
import crypto from 'crypto'

const prisma = new PrismaClient()
const TAG = 'community-seed-v1'
// 用户可见文案不再带标记；幂等靠 DB 查询与 referenceType / correlationId
const MSG_HELLO = (name) => `你好，我是${name || '同行'}。看到你最近在做相关需求，想聊聊怎么协作。`
const MSG_REPLY = '好的，我收到了，咱们平台里细聊。'

const args = new Set(process.argv.slice(2))
const DRY = args.has('--dry-run')
const limitArg = process.argv.find((a) => a.startsWith('--limit='))
const limitIdx = process.argv.indexOf('--limit')
const LIMIT = limitArg
  ? Number(limitArg.split('=')[1])
  : limitIdx >= 0
    ? Number(process.argv[limitIdx + 1])
    : 0

const stats = {
  users: 0,
  ledger: 0,
  follow: 0,
  circleMember: 0,
  circlesCreated: 0,
  message: 0,
  favorite: 0,
  serviceCard: 0,
  claim: 0,
  loopRun: 0,
  loopEvent: 0,
  order: 0,
  welfareReward: 0,
  skipped: {},
}

function bumpSkip(key) {
  stats.skipped[key] = (stats.skipped[key] || 0) + 1
}

function hashPick(seed, mod) {
  const h = crypto.createHash('sha1').update(String(seed)).digest()
  return h.readUInt32BE(0) % mod
}

function inviteCode(i) {
  return `HV${String(i).padStart(6, '0')}`
}

async function coverage() {
  const rows = await prisma.$queryRawUnsafe(`
    SELECT
      (SELECT COUNT(*)::int FROM "User") AS users,
      (SELECT COUNT(*)::int FROM "User" u WHERE EXISTS (SELECT 1 FROM "WalletLedger" w WHERE w."userId"=u.id AND w."referenceType"='${TAG}')) AS with_seed_ledger,
      (SELECT COUNT(*)::int FROM "User" u WHERE EXISTS (SELECT 1 FROM "Follow" f WHERE f."followerId"=u.id OR f."followingId"=u.id)) AS with_follow,
      (SELECT COUNT(*)::int FROM "User" u WHERE EXISTS (SELECT 1 FROM "CircleMember" cm WHERE cm."userId"=u.id)) AS with_circle,
      (SELECT COUNT(*)::int FROM "User" u WHERE EXISTS (SELECT 1 FROM "Message" m WHERE m."fromUserId"=u.id OR m."toUserId"=u.id)) AS with_message,
      (SELECT COUNT(*)::int FROM "User" u WHERE EXISTS (SELECT 1 FROM "ServiceCard" s WHERE s."userId"=u.id)) AS with_service_card,
      (SELECT COUNT(*)::int FROM "User" u WHERE EXISTS (SELECT 1 FROM "DemandFavorite" df WHERE df."userId"=u.id)) AS with_favorite,
      (SELECT COUNT(*)::int FROM "User" u WHERE EXISTS (SELECT 1 FROM "LoopRun" lr WHERE lr."initiatorRef"=('user:'||u.id))) AS with_loop_run,
      (SELECT COUNT(*)::int FROM "User" u WHERE EXISTS (SELECT 1 FROM "Order" o WHERE o."requesterId"=u.id OR o."providerId"=u.id)) AS with_order
  `)
  return rows[0]
}

async function main() {
  console.log(`[${TAG}] dry=${DRY} limit=${LIMIT || 'ALL'}`)

  const users = await prisma.user.findMany({
    select: { id: true, nickname: true, points: true, cityCode: true },
    orderBy: { createdAt: 'asc' },
    ...(LIMIT > 0 ? { take: LIMIT } : {}),
  })
  stats.users = users.length
  if (users.length === 0) throw new Error('no users')

  const offerings = await prisma.loopOffering.findMany({
    where: { status: 'ACTIVE' },
    select: {
      id: true,
      definitionId: true,
      definition: { select: { loopKind: true } },
    },
    take: 40,
  })
  if (offerings.length === 0) throw new Error('no LoopOffering')

  const activeDemands = await prisma.demand.findMany({
    where: { status: 'ACTIVE', deletedAt: null },
    select: { id: true, userId: true, minPrice: true, title: true },
    take: 3000,
  })
  const demandsByOwner = new Map()
  for (const d of activeDemands) {
    if (!demandsByOwner.has(d.userId)) demandsByOwner.set(d.userId, [])
    demandsByOwner.get(d.userId).push(d)
  }
  const foreignDemands = activeDemands

  const welfareDemand = await prisma.demand.findFirst({
    where: { isPublicWelfare: true, status: 'ACTIVE' },
    select: { id: true },
  })

  // --- Circles: ensure hub circles exist ---
  const CIRCLE_COUNT = Math.max(8, Math.ceil(users.length / 120))
  const circleIds = []
  const CIRCLE_NAMES = ['上海协作圈', '杭州共创组', '深圳产品会', '北京研究社', '成都设计局', '南京交付组', '广州增长营', '苏州体验站']
  for (let i = 0; i < CIRCLE_COUNT; i++) {
    const name = CIRCLE_NAMES[i % CIRCLE_NAMES.length] + (i >= CIRCLE_NAMES.length ? `·${i + 1}` : '')
    let circle = await prisma.circle.findFirst({ where: { name } })
    if (!circle) {
      // also match legacy seed names
      circle = await prisma.circle.findFirst({
        where: { name: `${TAG}·回社区-${i + 1}` },
      })
    }
    if (!circle) {
      const owner = users[i % users.length]
      if (DRY) {
        stats.circlesCreated++
        circleIds.push(`dry-circle-${i}`)
        continue
      }
      circle = await prisma.circle.create({
        data: {
          name,
          description: '同城协作与需求对接',
          type: 'PUBLIC',
          ownerId: owner.id,
          cityCode: owner.cityCode || '310000',
          inviteCode: inviteCode(1000 + i),
          memberCount: 1,
          status: 'ACTIVE',
        },
      })
      await prisma.circleMember.upsert({
        where: { circleId_userId: { circleId: circle.id, userId: owner.id } },
        create: { circleId: circle.id, userId: owner.id, role: 'OWNER' },
        update: {},
      })
      stats.circlesCreated++
    }
    circleIds.push(circle.id)
  }

  // Preload existing seed ledgers / loop correlations for idempotency
  const existingLedgers = new Set(
    (
      await prisma.walletLedger.findMany({
        where: { referenceType: TAG },
        select: { userId: true },
      })
    ).map((r) => r.userId),
  )
  const existingLoopCorr = new Set(
    (
      await prisma.loopRun.findMany({
        where: { correlationId: { startsWith: `${TAG}:` } },
        select: { correlationId: true },
      })
    )
      .map((r) => r.correlationId)
      .filter(Boolean),
  )
  const usersWithCard = new Set(
    (
      await prisma.serviceCard.findMany({
        select: { userId: true },
        distinct: ['userId'],
      })
    ).map((r) => r.userId),
  )
  const usersInCircle = new Set(
    (
      await prisma.circleMember.findMany({
        where: { userId: { in: users.map((u) => u.id) } },
        select: { userId: true },
      })
    ).map((r) => r.userId),
  )
  const orderedDemands = await prisma.order.findMany({ select: { demandId: true } })
  const orderedDemandIds = new Set(orderedDemands.map((o) => o.demandId))

  const BATCH = 40
  for (let offset = 0; offset < users.length; offset += BATCH) {
    const batch = users.slice(offset, offset + BATCH)
    for (let bi = 0; bi < batch.length; bi++) {
      const user = batch[bi]
      const globalIndex = offset + bi
      const neighbor1 = users[(globalIndex + 1) % users.length]
      const neighbor2 = users[(globalIndex + 3) % users.length]
      const neighbor3 = users[(globalIndex + 7) % users.length]
      const neighbors = [neighbor1, neighbor2, neighbor3].filter((n) => n.id !== user.id)

      // 1) Wallet ledger
      if (existingLedgers.has(user.id)) {
        bumpSkip('ledger')
      } else if (!DRY) {
        const credited = Number(user.points || 0) < 1000 ? 5000 : 1
        const updated = await prisma.user.update({
          where: { id: user.id },
          data: { points: { increment: credited } },
          select: { points: true },
        })
        const balanceAfter = Number(updated.points)
        await prisma.walletLedger.create({
          data: {
            userId: user.id,
            type: 'CREDIT',
            amount: credited,
            balanceAfter,
            referenceType: TAG,
            referenceId: user.id,
            memo: `${TAG} 社区开户流水（可见性补种）`,
          },
        })
        existingLedgers.add(user.id)
        stats.ledger++
      } else {
        stats.ledger++
      }

      // 2) Follows
      for (const n of neighbors.slice(0, 2)) {
        if (DRY) {
          stats.follow++
          continue
        }
        try {
          await prisma.follow.create({
            data: { followerId: user.id, followingId: n.id },
          })
          stats.follow++
        } catch {
          bumpSkip('follow')
        }
      }

      // 3) Circle membership
      const circleId = circleIds[globalIndex % circleIds.length]
      if (typeof circleId === 'string' && circleId.startsWith('dry-')) {
        stats.circleMember++
      } else if (usersInCircle.has(user.id)) {
        bumpSkip('circle')
      } else if (!DRY) {
        try {
          await prisma.circleMember.create({
            data: { circleId, userId: user.id, role: 'MEMBER' },
          })
          await prisma.circle.update({
            where: { id: circleId },
            data: { memberCount: { increment: 1 } },
          })
          usersInCircle.add(user.id)
          stats.circleMember++
        } catch {
          bumpSkip('circle')
        }
      } else {
        stats.circleMember++
      }

      // 4) DM with neighbor1 (both directions), idempotent by content+pair
      const peer = neighbor1.id === user.id ? neighbor2 : neighbor1
      if (peer) {
        const contentA = MSG_HELLO(user.nickname)
        const contentB = MSG_REPLY
        if (DRY) {
          stats.message += 2
        } else {
          const exists = await prisma.message.findFirst({
            where: {
              fromUserId: user.id,
              toUserId: peer.id,
              content: contentA,
            },
            select: { id: true },
          })
          if (exists) {
            bumpSkip('message')
          } else {
            await prisma.message.createMany({
              data: [
                {
                  fromUserId: user.id,
                  toUserId: peer.id,
                  content: contentA,
                  type: 'TEXT',
                  isRead: true,
                },
                {
                  fromUserId: peer.id,
                  toUserId: user.id,
                  content: contentB,
                  type: 'TEXT',
                  isRead: false,
                },
              ],
            })
            stats.message += 2
          }
        }
      }

      // 5) Favorite one foreign demand
      const favCandidates = foreignDemands.filter((d) => d.userId !== user.id)
      if (favCandidates.length > 0) {
        const pick = favCandidates[hashPick(user.id + ':fav', favCandidates.length)]
        if (DRY) {
          stats.favorite++
        } else {
          try {
            await prisma.demandFavorite.create({
              data: { userId: user.id, demandId: pick.id },
            })
            stats.favorite++
          } catch {
            bumpSkip('favorite')
          }
        }
      }

      // 6) Service card for ~30%
      const wantCard = hashPick(user.id + ':card', 10) < 3
      if (wantCard) {
        if (usersWithCard.has(user.id)) {
          bumpSkip('serviceCard')
        } else if (DRY) {
          stats.serviceCard++
          stats.claim++
        } else {
          const title = `${(user.nickname || '创作者').slice(0, 12)}的服务卡`
          const card = await prisma.serviceCard.create({
            data: {
              userId: user.id,
              title,
              summary: '可沟通范围、交付与档期',
              description: '平台内协作，细节以需求卡与成单约定为准。',
              category: '产品策略',
              serviceType: 'ONLINE',
              status: 'PUBLISHED',
              isPublic: true,
              publishedAt: new Date(),
              tags: ['协作', '交付'],
              paths: [],
            },
          })
          await prisma.serviceCardClaim.create({
            data: {
              serviceCardId: card.id,
              label: '可用性',
              description: '社区补种 claim',
              sortOrder: 0,
            },
          })
          usersWithCard.add(user.id)
          stats.serviceCard++
          stats.claim++
        }
      }

      // 7) Loop runs (2–3) keyed by correlationId
      const runCount = 2 + (hashPick(user.id + ':runs', 2) === 0 ? 1 : 0)
      for (let r = 0; r < runCount; r++) {
        const corr = `${TAG}:${user.id}:${r}`
        if (existingLoopCorr.has(corr)) {
          bumpSkip('loopRun')
          continue
        }
        const off = offerings[hashPick(user.id + ':off:' + r, offerings.length)]
        if (DRY) {
          stats.loopRun++
          stats.loopEvent += 2
          continue
        }
        const run = await prisma.loopRun.create({
          data: {
            definitionId: off.definitionId,
            offeringId: off.id,
            loopKind: off.definition.loopKind,
            status: r === 0 ? 'SUCCEEDED' : hashPick(corr, 5) === 0 ? 'EXECUTING' : 'SUCCEEDED',
            initiatorRef: `user:${user.id}`,
            receiverRef: null,
            inputJson: { seed: TAG, note: 'community backfill' },
            expectedOutcome: { ok: true },
            actualOutcome: r === 0 ? { ok: true, seeded: true } : undefined,
            correlationId: corr,
            startedAt: new Date(Date.now() - (r + 1) * 86400000),
            completedAt: r === 0 ? new Date() : null,
          },
        })
        await prisma.loopEvent.createMany({
          data: [
            {
              loopRunId: run.id,
              type: 'COMMUNITY_SEED_TRIGGERED',
              actorRef: `user:${user.id}`,
              visibility: 'ACTOR',
              payload: { tag: TAG },
              idempotencyKey: `${corr}:trig`,
            },
            {
              loopRunId: run.id,
              type: 'COMMUNITY_SEED_PROGRESS',
              actorRef: `user:${user.id}`,
              visibility: 'ACTOR',
              payload: { step: 1 },
              idempotencyKey: `${corr}:prog`,
            },
          ],
        })
        existingLoopCorr.add(corr)
        stats.loopRun++
        stats.loopEvent += 2
      }

      // 8) Welfare reward for ~5%
      if (welfareDemand && hashPick(user.id + ':welfare', 20) === 0) {
        if (DRY) {
          stats.welfareReward++
        } else {
          const exists = await prisma.welfareReward.findFirst({
            where: { providerId: user.id, demandId: welfareDemand.id },
            select: { id: true },
          })
          if (exists) bumpSkip('welfare')
          else {
            await prisma.welfareReward.create({
              data: {
                demandId: welfareDemand.id,
                providerId: user.id,
                amount: 10,
                isSpiritual: false,
                rewardType: 'random',
                badge: TAG,
              },
            })
            stats.welfareReward++
          }
        }
      }
    }
    console.log(`  batch ${Math.min(offset + BATCH, users.length)}/${users.length}`)
  }

  // 9) Light orders for ~13% of users (pair requester/provider on unordered demands)
  const orderTarget = Math.max(1, Math.floor(users.length * 0.13))
  let ordersMade = 0
  for (let i = 0; i < users.length && ordersMade < orderTarget; i++) {
    const requester = users[i]
    const provider = users[(i + 11) % users.length]
    if (requester.id === provider.id) continue
    const owned = (demandsByOwner.get(requester.id) || []).filter(
      (d) => !orderedDemandIds.has(d.id),
    )
    if (owned.length === 0) continue
    const demand = owned[0]
    if (DRY) {
      stats.order++
      ordersMade++
      orderedDemandIds.add(demand.id)
      continue
    }
    try {
      await prisma.order.create({
        data: {
          demandId: demand.id,
          requesterId: requester.id,
          providerId: provider.id,
          agreedPrice: Number(demand.minPrice) || 100,
          status: ordersMade % 5 === 0 ? 'DISPUTED' : 'COMPLETED',
          paidAt: new Date(Date.now() - 7 * 86400000),
          completedAt: ordersMade % 5 === 0 ? null : new Date(Date.now() - 2 * 86400000),
        },
      })
      await prisma.demand.update({
        where: { id: demand.id },
        data: { status: ordersMade % 5 === 0 ? 'IN_PROGRESS' : 'COMPLETED' },
      }).catch(() => {})
      orderedDemandIds.add(demand.id)
      stats.order++
      ordersMade++
    } catch {
      bumpSkip('order')
    }
  }

  // Sync circle memberCounts for seed circles
  if (!DRY) {
    for (const id of circleIds) {
      if (typeof id !== 'string' || id.startsWith('dry-')) continue
      const c = await prisma.circleMember.count({ where: { circleId: id } })
      await prisma.circle.update({ where: { id }, data: { memberCount: c } })
    }
  }

  const cov = await coverage()
  console.log(JSON.stringify({ stats, coverage: cov }, null, 2))
}

main()
  .catch((e) => {
    console.error(e)
    process.exit(1)
  })
  .finally(async () => {
    await prisma.$disconnect()
  })
