import 'server-only'
import { get, list, put } from '@vercel/blob'

export type BuildRecord = {
  id: string
  appName: string
  fileName: string
  version: string
  abi: string
  createdAt: string
  runId: number | null
  apkPathname: string | null
  apkName: string | null
  apkSize: number | null
}

const recordPath = (id: string) => `builds/${id}.json`

export function isValidBuildId(id: string) {
  return /^[a-z0-9]{6,32}$/.test(id)
}

export async function saveBuild(record: BuildRecord) {
  await put(recordPath(record.id), JSON.stringify(record), {
    access: 'private',
    contentType: 'application/json',
    addRandomSuffix: false,
    allowOverwrite: true,
  })
}

export async function readBuild(id: string): Promise<BuildRecord | null> {
  const result = await get(recordPath(id), { access: 'private' })
  if (!result || result.statusCode !== 200) return null
  return (await new Response(result.stream).json()) as BuildRecord
}

export async function listBuilds(limit = 8): Promise<BuildRecord[]> {
  const { blobs } = await list({ prefix: 'builds/', limit: 100 })
  const latest = blobs
    .sort((a, b) => b.uploadedAt.getTime() - a.uploadedAt.getTime())
    .slice(0, limit)
  const records = await Promise.all(
    latest.map((blob) => readBuild(blob.pathname.replace(/^builds\/|\.json$/g, ''))),
  )
  return records
    .filter((r): r is BuildRecord => r !== null)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
}
