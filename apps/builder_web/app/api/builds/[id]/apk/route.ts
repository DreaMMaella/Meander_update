import { get } from '@vercel/blob'
import { NextResponse } from 'next/server'
import { isValidBuildId, readBuild } from '@/lib/builds'

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  if (!isValidBuildId(id)) return NextResponse.json({ error: 'Неверный ID' }, { status: 400 })

  const record = await readBuild(id)
  if (!record?.apkPathname) {
    return NextResponse.json({ error: 'APK ещё не готов' }, { status: 404 })
  }

  const file = await get(record.apkPathname, { access: 'private' })
  if (!file || file.statusCode !== 200) {
    return NextResponse.json({ error: 'APK не найден' }, { status: 404 })
  }

  const fileName = record.apkName ?? 'quest.apk'
  return new NextResponse(file.stream, {
    headers: {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Disposition': `attachment; filename="quest.apk"; filename*=UTF-8''${encodeURIComponent(fileName)}`,
      ...(record.apkSize ? { 'Content-Length': String(record.apkSize) } : {}),
      'Cache-Control': 'private, no-store',
    },
  })
}
