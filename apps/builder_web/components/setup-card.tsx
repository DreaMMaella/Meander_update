import { KeyRound } from 'lucide-react'

export function SetupCard({ repo }: { repo: string }) {
  return (
    <section
      aria-labelledby="setup-title"
      className="flex flex-col gap-5 rounded-xl border border-accent/40 bg-surface p-6"
    >
      <div className="flex items-center gap-3">
        <span className="flex size-9 items-center justify-center rounded-lg bg-accent/15 text-accent">
          <KeyRound className="size-5" aria-hidden />
        </span>
        <h2 id="setup-title" className="text-lg font-semibold">
          Остался один шаг — токен GitHub
        </h2>
      </div>
      <p className="leading-relaxed text-muted">
        Сборщик запускает сборку в твоём репозитории <span className="font-mono text-foreground">{repo}</span>,
        поэтому ему нужен доступ.
      </p>
      <ol className="flex list-decimal flex-col gap-2 pl-5 leading-relaxed text-muted marker:text-accent">
        <li>
          Открой{' '}
          <a
            className="text-foreground underline underline-offset-4 hover:text-accent"
            href="https://github.com/settings/personal-access-tokens/new"
            target="_blank"
            rel="noreferrer"
          >
            github.com/settings/personal-access-tokens/new
          </a>
        </li>
        <li>
          Repository access → <span className="text-foreground">Only select repositories</span> → {repo}
        </li>
        <li>
          Permissions: <span className="text-foreground">Actions — Read and write</span>,{' '}
          <span className="text-foreground">Contents — Read and write</span>
        </li>
        <li>
          Скопируй токен и добавь его в v0: настройки справа сверху → Vars →{' '}
          <span className="font-mono text-foreground">GITHUB_TOKEN</span>
        </li>
      </ol>
    </section>
  )
}
