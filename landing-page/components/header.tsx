'use client'

import { Moon, Sun } from 'lucide-react'
import Link from 'next/link'
import Image from 'next/image'
import { useEffect, useState } from 'react'

export function Header() {
  const [isDark, setIsDark] = useState(false)
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
    setIsDark(document.documentElement.classList.contains('dark'))
  }, [])

  const toggleTheme = () => {
    const newIsDark = !isDark
    setIsDark(newIsDark)

    if (newIsDark) {
      document.documentElement.classList.add('dark')
      localStorage.setItem('theme', 'dark')
    } else {
      document.documentElement.classList.remove('dark')
      localStorage.setItem('theme', 'light')
    }
  }

  if (!mounted) return null

  return (
    <header className="fixed top-0 left-0 right-0 z-50 bg-background/80 backdrop-blur-xl border-b border-border">
      <nav className="max-w-7xl mx-auto px-6 py-4 flex items-center justify-between">
        <Link href="#" className="flex items-center gap-2">
          <Image
            src="/logo.png"
            alt="Commit+ Logo"
            width={32}
            height={32}
            className="w-8 h-8"
          />
          <span className="font-bold text-lg tracking-tight">Commit+</span>
        </Link>

        <div className="hidden md:flex items-center gap-8">
          <Link href="#features" className="text-sm font-medium hover:text-primary transition">
            Features
          </Link>
          <Link href="#pricing" className="text-sm font-medium hover:text-primary transition">
            Pricing
          </Link>
          <Link href="#blog" className="text-sm font-medium hover:text-primary transition">
            Blog
          </Link>
          <Link href="#docs" className="text-sm font-medium hover:text-primary transition">
            Docs
          </Link>
        </div>

        <div className="flex items-center gap-4">
          <button
            onClick={toggleTheme}
            className="p-2 rounded-full hover:bg-secondary transition"
            aria-label="Toggle theme"
          >
            {isDark ? <Sun size={20} /> : <Moon size={20} />}
          </button>

          <Link
            href="#download"
            className="bg-primary text-primary-foreground px-6 py-2 rounded-full font-medium hover:opacity-90 transition"
          >
            Download
          </Link>
        </div>
      </nav>
    </header>
  )
}
