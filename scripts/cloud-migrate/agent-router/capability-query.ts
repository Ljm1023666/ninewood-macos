const CAPABILITY_PATTERNS = [
  /你能做什么/,
  /你会做什么/,
  /你能帮我做什么/,
  /有什么功能/,
  /能帮我什么/,
  /你可以做什么/,
]

export function isCapabilityQuery(message: string): boolean {
  const compact = message.replace(/\s/g, '')
  return CAPABILITY_PATTERNS.some((re) => re.test(compact))
}

export const CAPABILITY_REPLY =
  '我在九木平台可以搜索、创建、申请、查看各种需求。'
