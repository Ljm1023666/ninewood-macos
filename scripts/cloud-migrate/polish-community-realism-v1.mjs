#!/usr/bin/env node
/**
 * polish-community-realism-v1 — 把假昵称/空头像/带 [community-seed-v1] 前缀的对话
 * 改成真实中文名 + 真实头像路径 + 自然私聊文案。
 *
 * 用法（/opt/ninewood/server）:
 *   node scripts/polish-community-realism-v1.mjs --dry-run
 *   node scripts/polish-community-realism-v1.mjs
 */
import { PrismaClient } from '@prisma/client'
import crypto from 'crypto'
import fs from 'fs'
import path from 'path'

const prisma = new PrismaClient()
const DRY = process.argv.includes('--dry-run')
const AVATAR_DIR = path.resolve('uploads/avatars')

const NICKNAMES = [
  '林夏', '陈述', '张默', '方舟', '许言', '程野', '周屿', '乔安', '陈知远', '平波',
  '沈清禾', '陆晚舟', '顾言蹊', '苏念安', '叶知秋', '江晚吟', '白书瑶', '宋辞川', '温以宁', '谢临风',
  '何予安', '梁小满', '韩听雨', '唐一诺', '罗清欢', '高景行', '冯沐阳', '丁未央', '曹予怀', '彭知微',
  '袁望舒', '蒋南枝', '蔡明川', '余安然', '杜清越', '叶栖迟', '夏临安', '姜予白', '范知夏', '邹晚晴',
  '魏听澜', '薛清平', '严予舟', '华知远', '金望川', '陶清禾', '尹临溪', '黎小棠', '易安之', '常予微',
  '施清和', '傅望舒', '皮临风', '卞知夏', '齐晚舟', '康予安', '伍清欢', '余景行', '元小满', '卜听雨',
  '顾清越', '孟临安', '黄知微', '萧望川', '徐清平', '孙予怀', '马晚晴', '朱听澜', '胡知远', '郭临溪',
  '林望舒', '何小棠', '高安之', '梁予微', '宋清和', '郑望舒', '王临风', '冯知夏', '陈晚舟', '楚予安',
  '云清欢', '墨景行', '青小满', '白听雨', '玄清越', '岚临安', '寒知微', '霜望川', '雪清平', '露予怀',
  '阿禾', '小满', '晚舟', '清欢', '临川', '知夏', '望舒', '听雨', '予安', '景行',
  '木子李', '三点水', '言午许', '双木林', '耳东陈', '立早章', '古月胡', '口天吴', '弓长张', '木易杨',
  '设计师阿乔', '产品阿默', '研究林夏', '前端许言', '后端陈述', '增长程野', '品牌周屿', '视觉方舟',
  '南京老周', '上海阿宁', '杭州小满', '成都清禾', '深圳临风', '广州知远', '北京望舒', '苏州听雨',
  '水电张师傅', '保洁刘姐', '摄影阿凯', '家教小林', '律所王律', '会计小蔡', '健身阿杰', '咖啡阿夏',
  '插画阿鱼', '文案阿舟', '运营小南', '策划阿远', '翻译小安', '配音阿岚', '剪辑小禾', '建模阿川',
]

const CHAT_TEMPLATES = [
  (a, b) => `你好，我是${a}。看到你最近在做相关需求，想聊聊怎么协作。`,
  (a, b) => `${b}你好，我这边可以先对齐一下范围和交付节奏。`,
  (a, b) => `方便的话发一下你的时间窗口，我排个简短通话。`,
  (a, b) => `好的，我先把要点整理成三条，今晚发你。`,
  (a, b) => `收到，材料我看过了，整体方向没问题。`,
  (a, b) => `那我们按平台内沟通推进，细节放需求卡里。`,
  (a, b) => `我这边这周有空档，周三或周五下午都可以。`,
  (a, b) => `可以，预算和验收标准你定个底线我跟着来。`,
  (a, b) => `刚看了你的服务卡，风格挺合适，想请你估个工期。`,
  (a, b) => `没问题，我先收藏了你的需求，回头细聊。`,
]

const stats = {
  nickUpdated: 0,
  avatarUpdated: 0,
  msgUpdated: 0,
  cardTitleUpdated: 0,
  skipped: 0,
}

function hash(s) {
  return crypto.createHash('sha1').update(String(s)).digest()
}

function pickNick(userId, used) {
  for (let i = 0; i < NICKNAMES.length * 3; i++) {
    const idx = hash(userId + ':' + i).readUInt32BE(0) % NICKNAMES.length
    const base = NICKNAMES[idx]
    const nick = i < NICKNAMES.length ? base : `${base}${String.fromCharCode(65 + (i % 26))}`
    if (!used.has(nick)) return nick
  }
  return `访客${userId.slice(0, 4)}`
}

function isFakeNick(n) {
  if (!n) return true
  return /^(用户_|发卡_|收卡_|种子|补种)/.test(n) || /community-seed|测试账号|九木测试/.test(n)
}

function listAvatars() {
  const files = fs.readdirSync(AVATAR_DIR).filter((f) => /\.(jpe?g|png|webp)$/i.test(f))
  if (files.length === 0) throw new Error(`no avatars in ${AVATAR_DIR}`)
  return files.sort()
}

async function main() {
  console.log(`[polish-realism] dry=${DRY}`)
  const avatars = listAvatars()
  console.log(`avatars=${avatars.length}`)

  const users = await prisma.user.findMany({
    select: { id: true, nickname: true, avatarUrl: true },
    orderBy: { createdAt: 'asc' },
  })

  const usedNicks = new Set(
    users.map((u) => u.nickname).filter((n) => n && !isFakeNick(n)),
  )

  // 1) Fix fake nicknames + missing avatars for ALL users missing avatar
  for (const u of users) {
    const needNick = isFakeNick(u.nickname)
    const needAvatar = !u.avatarUrl || !String(u.avatarUrl).trim()
    if (!needNick && !needAvatar) {
      stats.skipped++
      continue
    }
    const data = {}
    if (needNick) {
      data.nickname = pickNick(u.id, usedNicks)
      usedNicks.add(data.nickname)
      stats.nickUpdated++
    }
    if (needAvatar) {
      const file = avatars[hash(u.id).readUInt32BE(0) % avatars.length]
      data.avatarUrl = `/uploads/avatars/${file}`
      stats.avatarUpdated++
    }
    if (DRY) continue
    await prisma.user.update({ where: { id: u.id }, data })
  }

  // Refresh nick map after updates
  const nickById = new Map()
  const refreshed = DRY
    ? users.map((u) => ({
        ...u,
        nickname: isFakeNick(u.nickname) ? pickNick(u.id, usedNicks) : u.nickname,
      }))
    : await prisma.user.findMany({ select: { id: true, nickname: true } })
  for (const u of refreshed) nickById.set(u.id, u.nickname || '朋友')

  // 2) Rewrite seed-tagged DMs into natural chat (keep same pair, update content)
  const seedMsgs = await prisma.message.findMany({
    where: { content: { startsWith: '[community-seed-v1]' } },
    select: { id: true, fromUserId: true, toUserId: true, content: true },
    orderBy: { createdAt: 'asc' },
  })

  for (const m of seedMsgs) {
    const fromName = nickById.get(m.fromUserId) || '我'
    const toName = nickById.get(m.toUserId) || '你'
    const isReply = m.content.includes('欢迎') || m.content.includes('收到')
    let content
    if (isReply) {
      const replies = [
        `好的，我收到了，咱们平台里细聊。`,
        `没问题，材料我今晚回你。`,
        `可以，预算和排期我按你说的来。`,
        `收到，先对齐验收标准再开工。`,
        `好，我先准备一版提纲发你。`,
      ]
      content = replies[hash(m.id + ':r').readUInt32BE(0) % replies.length]
    } else {
      const tpl = CHAT_TEMPLATES[hash(m.id).readUInt32BE(0) % CHAT_TEMPLATES.length]
      content = tpl(fromName, toName)
    }

    if (!DRY) {
      await prisma.message.update({
        where: { id: m.id },
        data: { content },
      })
    }
    stats.msgUpdated++
  }

  // 3) Soften service card titles that scream seed
  const cards = await prisma.serviceCard.findMany({
    where: { title: { contains: 'community-seed-v1' } },
    select: { id: true, userId: true, title: true },
  })
  for (const c of cards) {
    const nick = nickById.get(c.userId) || '创作者'
    const title = `${nick}的服务卡`
    if (!DRY) {
      await prisma.serviceCard.update({
        where: { id: c.id },
        data: {
          title,
          summary: '可沟通范围、交付与档期',
          description: '平台内协作，细节以需求卡与成单约定为准。',
        },
      })
    }
    stats.cardTitleUpdated++
  }

  // 4) Circle names
  const circles = await prisma.circle.findMany({
    where: { name: { startsWith: 'community-seed-v1' } },
    select: { id: true, name: true },
  })
  const cityNames = ['上海协作圈', '杭州共创组', '深圳产品会', '北京研究社', '成都设计局', '南京交付组', '广州增长营', '苏州体验站']
  for (let i = 0; i < circles.length; i++) {
    const name = cityNames[i % cityNames.length]
    if (!DRY) {
      await prisma.circle.update({
        where: { id: circles[i].id },
        data: { name, description: '同城协作与需求对接' },
      })
    }
  }

  const leftoverFake = await prisma.user.count({
    where: {
      OR: [
        { nickname: { startsWith: '用户_' } },
        { nickname: { startsWith: '发卡_' } },
        { nickname: { startsWith: '收卡_' } },
        { avatarUrl: null },
      ],
    },
  })
  const leftoverSeedMsg = await prisma.message.count({
    where: { content: { startsWith: '[community-seed-v1]' } },
  })

  console.log(
    JSON.stringify(
      {
        stats,
        circlesRenamed: circles.length,
        leftoverFake,
        leftoverSeedMsg: DRY ? leftoverSeedMsg : leftoverSeedMsg,
      },
      null,
      2,
    ),
  )
}

main()
  .catch((e) => {
    console.error(e)
    process.exit(1)
  })
  .finally(() => prisma.$disconnect())
