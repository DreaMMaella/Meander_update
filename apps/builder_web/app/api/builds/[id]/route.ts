import { put } from '@vercel/blob'
import { NextResponse } from 'next/server'
import { isValidBuildId, readBuild, saveBuild } from '@/lib/builds'
import { downloadApkFromRun, findRunId, getRunState } from '@/lib/github'

export const maxDuration = 120

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  if (!isValidBuildId(id)) return NextResponse.json({ error: 'Неверный ID' }, { status: 400 })

  const record = await readBuild(id)
  if (!record) return NextResponse.json({ error: 'Сборка не найдена' }, { status: 404 })

  try {
    if (!record.runId) {
      record.runId = await findRunId(id)
      if (!record.runId) {
        return NextResponse.json({ build: record, state: { status: 'starting' } })
      }
      await saveBuild(record)
    }

    const state = await getRunState(record.runId)

    if (state.status === 'success' && !record.apkPathname) {
      const apk = await downloadApkFromRun(record.runId)
      if (apk) {
        const pathname = `apk/${id}/${apk.name}`
        await put(pathname, Buffer.from(apk.data), {
          access: 'private',
          contentType: 'application/vnd.android.package-archive',
          addRandomSuffix: false,
          allowOverwrite: true,
        })
        record.apkPathname = pathname
        record.apkName = apk.name
        record.apkSize = apk.data.byteLength
        await saveBuild(record)
      }
    }

    return NextResponse.json({ build: record, state })
  } catch (error) {
    return NextResponse.json(
      { build: record, state: { status: 'unknown' }, error: (error as Error).message },
      { status: 200 },
    )
  }
}
