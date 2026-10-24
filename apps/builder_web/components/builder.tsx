'use client'

import { useState } from 'react'
import { BuildHistory } from './build-history'
import { BuildStatus } from './build-status'
import { QuestForm } from './quest-form'

export function Builder() {
  const [activeId, setActiveId] = useState<string | null>(null)

  return (
    <div className="flex flex-col gap-8">
      <QuestForm onStarted={setActiveId} />
      {activeId && <BuildStatus id={activeId} />}
      <BuildHistory activeId={activeId} onSelect={setActiveId} />
    </div>
  )
}
