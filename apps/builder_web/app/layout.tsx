import type { Metadata, Viewport } from 'next'
import { Geist, Geist_Mono } from 'next/font/google'
import './globals.css'

const geistSans = Geist({ subsets: ['latin', 'cyrillic'], variable: '--font-geist-sans' })
const geistMono = Geist_Mono({ subsets: ['latin', 'cyrillic'], variable: '--font-geist-mono' })

export const metadata: Metadata = {
  title: 'Meander — сборщик квестов в APK',
  description: 'Загрузи квест .mnd и получи готовое Android-приложение с плеером Meander.',
}

export const viewport: Viewport = {
  themeColor: '#0c0c0e',
  colorScheme: 'dark',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ru" className={`${geistSans.variable} ${geistMono.variable}`}>
      <body className="min-h-dvh font-sans antialiased">{children}</body>
    </html>
  )
}
