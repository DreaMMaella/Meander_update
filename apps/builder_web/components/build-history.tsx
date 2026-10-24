'use client'

import useSWR from 'swr'
import type { BuildRecord } from '@/lib/builds'

const fetcher = (url: string) => fetch(url).then((r) => r.json() as Promise<{ builds: BuildRecord[] }>)

const dateFormat = new Intl.DateTimeFormat('ru-RU', { dateStyle: 'short', timeStyle: 'short' })

export function BuildHistory({
  activeId,
  onSelect,
}: {
  activeId: string | null
  onSelect: (id: string) => void
}) {
  const { data, isLoading } = useSWR('/api/builds', fetcher)
  const builds = data?.builds ?? []

  return (
    <section aria-labelledby="history-title" className="flex flex-col gap-3">
      <h2 id="history-title" className="text-sm font-medium uppercase tracking-wider text-muted">
        Прошлые сборки
      </h2>
      {isLoading ? (
        <p className="text-sm text-muted">Загрузка…</p>
      ) : builds.length === 0 ? (
        <p className="text-sm text-muted">Пока ничего не собиралось.</p>
      ) : (
        <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-xl border border-border">
          {builds.map((b) => (
            <li key={b.id}>
              <button
                type="button"
                onClick={() => onSelect(b.id)}
                aria-current={b.id === activeId}
                className="flex w-full items-center justify-between gap-4 bg-surface px-4 py-3 text-left transition-colors hover:bg-surface-raised aria-[current=true]:bg-surface-raised"
              >
                <span className="flex min-w-0 flex-col">
                  <span className="truncate font-medium">{b.appName}</span>
                  <span className="truncate font-mono text-xs text-muted">
                    v{b.version} · {b.abi} · {dateFormat.format(new Date(b.createdAt))}
                  </span>
                </span>
                <span className={`shrink-0 text-xs ${b.apkPathname ? 'text-success' : 'text-muted'}`}>
                  {b.apkPathname ? 'APK готов' : 'Открыть'}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
