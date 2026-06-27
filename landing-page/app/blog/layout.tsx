import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Blog | Commit+',
  description: 'Latest stories, updates, and insights from the Commit+ team',
}

export default function BlogLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return <>{children}</>
}
