import Link from 'next/link'

export default function NotFound() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-background">
      <div className="text-center max-w-md px-6">
        <h1 className="text-6xl font-bold mb-4">404</h1>
        <p className="text-xl text-muted-foreground mb-8">Blog post not found</p>
        <Link href="/#blog" className="inline-flex items-center justify-center px-6 py-3 bg-primary text-primary-foreground rounded-2xl font-semibold hover:opacity-90 transition">
          Back to blog
        </Link>
      </div>
    </div>
  )
}
