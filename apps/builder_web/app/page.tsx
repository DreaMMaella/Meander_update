import { Builder } from '@/components/builder'
import { SetupCard } from '@/components/setup-card'
import { isConfigured, repo } from '@/lib/github'

export const dynamic = 'force-dynamic'

export default function Page() {
  const configured = isConfigured()

  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col gap-8 px-4 py-10 md:py-16">
      <header className="flex flex-col gap-3">
        <p className="font-mono text-xs uppercase tracking-widest text-accent">Meander · Quest Builder</p>
        <h1 className="text-balance text-3xl font-semibold tracking-tight md:text-4xl">
          Квест в отдельное Android-приложение
        </h1>
        <p className="max-w-xl text-pretty leading-relaxed text-muted">
          Загрузи файл <span className="font-mono text-foreground">.mnd</span>, нажми «Собрать APK» — сборка идёт на
          серверах GitHub. Ничего устанавливать не нужно: ни Flutter, ни Dart, ни Android Studio.
        </p>
      </header>

      {configured ? <Builder /> : <SetupCard repo={repo} />}

      <footer className="border-t border-border pt-6 font-mono text-xs text-muted">
        Сборка: GitHub Actions · {repo} · workflow build_quest_apk.yml
      </footer>
    </main>
  )
}
