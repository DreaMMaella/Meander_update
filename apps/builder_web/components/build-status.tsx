'use client'

import { CheckCircle2, Download, ExternalLink, Loader2, XCircle } from 'lucide-react'
import useSWR from 'swr'
import { formatBytes } from '@/lib/read-quest'
import type { BuildRecord } from '@/lib/builds'

export type BuildState = {
  status: 'starting' | 'queued' | 'running' | 'success' | 'failure' | 'unknown'
  htmlUrl?: string
  currentStep?: string | null
  completedSteps?: number
  totalSteps?: number
}

type StatusResponse = { build: BuildRecord; state: BuildState; error?: string }

const STEP_LABELS: Record<string, string> = {
  'Set up job': 'Подготовка сервера',
  'Run actions/checkout@v4': 'Загрузка кода плеера',
  'Fetch quest': 'Получение квеста',
  'Run actions/setup-java@v4': 'Установка Java',
  'Install Android NDK': 'Установка Android NDK',
  'Run dtolnay/rust-toolchain@stable': 'Установка Rust',
  'Run Swatinem/rust-cache@v2': 'Кэш Rust',
  'Install cargo-ndk': 'Установка cargo-ndk',
  'Run subosito/flutter-action@v2': 'Установка Flutter',
  'Configure signing': 'Подпись',
  'Build APK': 'Сборка APK',
  'Run actions/upload-artifact@v4': 'Выгрузка APK',
}

const fetcher = (url: string) => fetch(url).then((r) => r.json() as Promise<StatusResponse>)

export function useBuildStatus(id: string) {
  return useSWR(`/api/builds/${id}`, fetcher, {
    refreshInterval: (data) => {
      const s = data?.state.status
      if (s === 'failure') return 0
      if (s === 'success' && data?.build.apkPathname) return 0
      return 6000
    },
  })
}

export function BuildStatus({ id }: { id: string }) {
  const { data } = useBuildStatus(id)
  const state = data?.state
  const build = data?.build
  const status = state?.status ?? 'starting'
  const done = status === 'success' && build?.apkPathname
  const percent =
    state?.totalSteps && state.completedSteps !== undefined
      ? Math.round((state.completedSteps / state.totalSteps) * 100)
      : 0

  return (
    <section
      aria-live="polite"
      aria-labelledby={`status-${id}`}
      className="flex flex-col gap-4 rounded-xl border border-border bg-surface p-5 md:p-6"
    >
      <div className="flex items-start justify-between gap-4">
        <div className="flex min-w-0 flex-col gap-1">
          <h2 id={`status-${id}`} className="truncate text-lg font-semibold">
            {build?.appName ?? 'Сборка'}
          </h2>
          <p className="font-mono text-xs text-muted">
            {build ? `v${build.version} · ${build.abi} · ${build.fileName}` : id}
          </p>
        </div>
        <StatusBadge status={status} ready={Boolean(done)} />
      </div>

      {!done && status !== 'failure' && (
        <div className="flex flex-col gap-2">
          <div className="h-2 overflow-hidden rounded-full bg-surface-raised">
            <div
              className="h-full rounded-full bg-accent transition-[width] duration-700"
              style={{ width: `${status === 'success' ? 100 : Math.max(percent, 4)}%` }}
            />
          </div>
          <p className="text-sm text-muted">
            {status === 'starting' && 'GitHub принимает задачу…'}
            {status === 'queued' && 'В очереди на сервере сборки…'}
            {status === 'running' &&
              `${STEP_LABELS[state?.currentStep ?? ''] ?? state?.currentStep ?? 'Сборка'} · обычно 10–20 минут`}
            {status === 'success' && 'Забираю готовый APK…'}
            {status === 'unknown' && (data?.error ?? 'Не удалось получить статус, пробую снова…')}
          </p>
        </div>
      )}

      {status === 'failure' && (
        <p className="rounded-lg border border-danger/40 bg-danger/10 px-4 py-3 text-sm text-danger">
          Сборка упала на шаге «{STEP_LABELS[state?.currentStep ?? ''] ?? state?.currentStep ?? '—'}». Подробности — в
          логе GitHub.
        </p>
      )}

      <div className="flex flex-wrap gap-3">
        {done && (
          <a
            href={`/api/builds/${id}/apk`}
            className="flex h-11 items-center gap-2 rounded-lg bg-accent px-5 font-semibold text-accent-foreground transition-opacity hover:opacity-90"
          >
            <Download className="size-4" aria-hidden />
            Скачать APK{build?.apkSize ? ` · ${formatBytes(build.apkSize)}` : ''}
          </a>
        )}
        {state?.htmlUrl && (
          <a
            href={state.htmlUrl}
            target="_blank"
            rel="noreferrer"
            className="flex h-11 items-center gap-2 rounded-lg border border-border px-4 text-sm text-muted transition-colors hover:text-foreground"
          >
            <ExternalLink className="size-4" aria-hidden />
            Лог сборки
          </a>
        )}
      </div>
    </section>
  )
}

export function StatusBadge({ status, ready }: { status: BuildState['status']; ready: boolean }) {
  if (ready)
    return (
      <span className="flex shrink-0 items-center gap-1.5 rounded-full bg-success/15 px-3 py-1 text-xs font-medium text-success">
        <CheckCircle2 className="size-3.5" aria-hidden /> Готово
      </span>
    )
  if (status === 'failure')
    return (
      <span className="flex shrink-0 items-center gap-1.5 rounded-full bg-danger/15 px-3 py-1 text-xs font-medium text-danger">
        <XCircle className="size-3.5" aria-hidden /> Ошибка
      </span>
    )
  return (
    <span className="flex shrink-0 items-center gap-1.5 rounded-full bg-accent/15 px-3 py-1 text-xs font-medium text-accent">
      <Loader2 className="size-3.5 animate-spin" aria-hidden />
      {status === 'queued' ? 'В очереди' : 'Собирается'}
    </span>
  )
}
