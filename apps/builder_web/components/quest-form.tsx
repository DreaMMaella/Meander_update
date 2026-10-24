'use client'

import { upload } from '@vercel/blob/client'
import { FileArchive, Hammer, Loader2, Upload, X } from 'lucide-react'
import { useId, useRef, useState } from 'react'
import { mutate } from 'swr'
import { formatBytes, readQuestInfo, type QuestInfo } from '@/lib/read-quest'

const ABI_OPTIONS = [
  { value: 'arm64', label: 'arm64 — современные телефоны' },
  { value: 'arm', label: 'arm — старые телефоны' },
  { value: 'x64', label: 'x64 — эмуляторы' },
  { value: 'all', label: 'Все архитектуры (APK больше)' },
]

type Phase = 'idle' | 'uploading' | 'starting'

export function QuestForm({ onStarted }: { onStarted: (id: string) => void }) {
  const inputRef = useRef<HTMLInputElement>(null)
  const ids = { name: useId(), version: useId(), abi: useId(), file: useId() }
  const [file, setFile] = useState<File | null>(null)
  const [info, setInfo] = useState<QuestInfo | null>(null)
  const [appName, setAppName] = useState('')
  const [version, setVersion] = useState('1.0.0')
  const [abi, setAbi] = useState('arm64')
  const [phase, setPhase] = useState<Phase>('idle')
  const [progress, setProgress] = useState(0)
  const [error, setError] = useState<string | null>(null)
  const [dragging, setDragging] = useState(false)

  async function pickFile(next: File | null | undefined) {
    setError(null)
    if (!next) return
    if (!next.name.toLowerCase().endsWith('.mnd')) {
      setError('Нужен файл квеста с расширением .mnd')
      return
    }
    setFile(next)
    const questInfo = await readQuestInfo(next)
    setInfo(questInfo)
    if (!questInfo.valid) setError('Файл не похож на квест Meander — проверь, что это экспорт из редактора')
    setAppName(questInfo.title ?? next.name.replace(/\.mnd$/i, ''))
  }

  function reset() {
    setFile(null)
    setInfo(null)
    setAppName('')
    setError(null)
    if (inputRef.current) inputRef.current.value = ''
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault()
    if (!file || phase !== 'idle') return
    setError(null)
    setProgress(0)
    setPhase('uploading')
    try {
      const safeName = file.name.replace(/[^\p{L}\p{N}._-]+/gu, '_')
      const blob = await upload(`uploads/${safeName}`, file, {
        access: 'private',
        handleUploadUrl: '/api/upload',
        contentType: 'application/octet-stream',
        multipart: file.size > 8 * 1024 * 1024,
        onUploadProgress: ({ percentage }) => setProgress(percentage),
      })

      setPhase('starting')
      const res = await fetch('/api/builds', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pathname: blob.pathname, fileName: file.name, appName, version, abi }),
      })
      const data = (await res.json()) as { id?: string; error?: string }
      if (!res.ok || !data.id) throw new Error(data.error ?? 'Не удалось запустить сборку')

      onStarted(data.id)
      mutate('/api/builds')
      reset()
    } catch (err) {
      setError((err as Error).message)
    } finally {
      setPhase('idle')
    }
  }

  const busy = phase !== 'idle'
  const canSubmit = Boolean(file && info?.valid && appName.trim()) && !busy

  return (
    <form onSubmit={submit} className="flex flex-col gap-5 rounded-xl border border-border bg-surface p-5 md:p-6">
      {file ? (
        <div className="flex items-center gap-4 rounded-lg border border-border bg-surface-raised p-4">
          <span className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-accent/15 text-accent">
            <FileArchive className="size-5" aria-hidden />
          </span>
          <div className="flex min-w-0 flex-1 flex-col">
            <span className="truncate font-medium">{info?.title ?? file.name}</span>
            <span className="truncate font-mono text-xs text-muted">
              {file.name} · {formatBytes(file.size)}
              {info?.author ? ` · ${info.author}` : ''}
              {info?.encrypted ? ' · зашифрован' : ''}
            </span>
          </div>
          <button
            type="button"
            onClick={reset}
            disabled={busy}
            className="rounded-md p-2 text-muted transition-colors hover:bg-border hover:text-foreground disabled:opacity-50"
          >
            <X className="size-4" aria-hidden />
            <span className="sr-only">Убрать файл</span>
          </button>
        </div>
      ) : (
        <label
          htmlFor={ids.file}
          onDragOver={(e) => {
            e.preventDefault()
            setDragging(true)
          }}
          onDragLeave={() => setDragging(false)}
          onDrop={(e) => {
            e.preventDefault()
            setDragging(false)
            pickFile(e.dataTransfer.files[0])
          }}
          className={`flex cursor-pointer flex-col items-center gap-3 rounded-lg border border-dashed px-6 py-10 text-center transition-colors ${
            dragging ? 'border-accent bg-accent/5' : 'border-border hover:border-muted'
          }`}
        >
          <Upload className="size-6 text-accent" aria-hidden />
          <span className="font-medium">Перетащи сюда квест .mnd</span>
          <span className="text-sm text-muted">или нажми, чтобы выбрать файл</span>
        </label>
      )}
      <input
        ref={inputRef}
        id={ids.file}
        type="file"
        accept=".mnd"
        className="sr-only"
        onChange={(e) => pickFile(e.target.files?.[0])}
      />

      <div className="grid gap-4 md:grid-cols-[1fr_8rem]">
        <Field id={ids.name} label="Название приложения">
          <input
            id={ids.name}
            value={appName}
            onChange={(e) => setAppName(e.target.value)}
            maxLength={60}
            placeholder="Мой квест"
            required
            className={inputClass}
          />
        </Field>
        <Field id={ids.version} label="Версия">
          <input
            id={ids.version}
            value={version}
            onChange={(e) => setVersion(e.target.value)}
            pattern="\d+(\.\d+){0,3}"
            required
            className={`${inputClass} font-mono`}
          />
        </Field>
      </div>

      <Field id={ids.abi} label="Для каких устройств">
        <select id={ids.abi} value={abi} onChange={(e) => setAbi(e.target.value)} className={inputClass}>
          {ABI_OPTIONS.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
      </Field>

      {error && (
        <p role="alert" className="rounded-lg border border-danger/40 bg-danger/10 px-4 py-3 text-sm text-danger">
          {error}
        </p>
      )}

      <button
        type="submit"
        disabled={!canSubmit}
        className="flex h-12 items-center justify-center gap-2 rounded-lg bg-accent px-6 font-semibold text-accent-foreground transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-40"
      >
        {busy ? <Loader2 className="size-5 animate-spin" aria-hidden /> : <Hammer className="size-5" aria-hidden />}
        {phase === 'uploading'
          ? `Загрузка… ${Math.round(progress)}%`
          : phase === 'starting'
            ? 'Запускаю сборку…'
            : 'Собрать APK'}
      </button>
    </form>
  )
}

const inputClass =
  'h-11 w-full rounded-lg border border-border bg-surface-raised px-3 text-foreground outline-none transition-colors placeholder:text-muted focus:border-accent'

function Field({ id, label, children }: { id: string; label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-2">
      <label htmlFor={id} className="text-sm text-muted">
        {label}
      </label>
      {children}
    </div>
  )
}
