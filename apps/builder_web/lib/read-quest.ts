import { strFromU8, unzipSync } from 'fflate'

export type QuestInfo = {
  title: string | null
  author: string | null
  encrypted: boolean
  valid: boolean
}

export async function readQuestInfo(file: File): Promise<QuestInfo> {
  const bytes = new Uint8Array(await file.arrayBuffer())
  const header = strFromU8(bytes.subarray(0, 8))

  if (header === 'MND_SEC_') return { title: null, author: null, encrypted: true, valid: true }

  const zipBytes =
    header === 'MND_ZIP_' ? bytes.subarray(8) : bytes[0] === 0x50 && bytes[1] === 0x4b ? bytes : null
  if (!zipBytes) return { title: null, author: null, encrypted: false, valid: false }

  try {
    const files = unzipSync(zipBytes, { filter: (f) => f.name === 'config.json' })
    const config = files['config.json'] ? JSON.parse(strFromU8(files['config.json'])) : {}
    return {
      title: typeof config.title === 'string' ? config.title : null,
      author: typeof config.author === 'string' ? config.author : null,
      encrypted: false,
      valid: true,
    }
  } catch {
    return { title: null, author: null, encrypted: false, valid: false }
  }
}

export function formatBytes(size: number) {
  if (size < 1024) return `${size} Б`
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} КБ`
  return `${(size / 1024 / 1024).toFixed(1)} МБ`
}
