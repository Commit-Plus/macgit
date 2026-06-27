import { getBlogPost, getAllBlogSlugs, blogPosts } from '@/lib/blog-data'
import { ArrowLeft, Calendar, Clock } from 'lucide-react'
import Link from 'next/link'
import { notFound } from 'next/navigation'

export async function generateStaticParams() {
  return getAllBlogSlugs()
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params
  const post = getBlogPost(slug)

  if (!post) {
    return {
      title: 'Blog Post Not Found',
      description: 'The blog post you&apos;re looking for doesn&apos;t exist.',
    }
  }

  return {
    title: `${post.title} | Commit+`,
    description: post.excerpt,
  }
}

export default async function BlogDetailPage({
  params,
}: {
  params: Promise<{ slug: string }>
}) {
  const { slug } = await params
  const post = getBlogPost(slug)

  if (!post) {
    notFound()
  }

  const currentIndex = blogPosts.findIndex(p => p.slug === post.slug)
  const previousPost = currentIndex > 0 ? blogPosts[currentIndex - 1] : null
  const nextPost = currentIndex < blogPosts.length - 1 ? blogPosts[currentIndex + 1] : null

  return (
    <div className="min-h-screen bg-background">
      {/* Header Navigation */}
      <header className="sticky top-0 z-40 bg-card/80 backdrop-blur border-b border-border">
        <div className="max-w-4xl mx-auto px-6 py-4 flex items-center">
          <Link
            href="/#blog"
            className="flex items-center gap-2 text-muted-foreground hover:text-foreground transition"
          >
            <ArrowLeft size={20} />
            <span>Back to blog</span>
          </Link>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-4xl mx-auto px-6 py-16">
        {/* Article Header */}
        <article>
          <div className="mb-8">
            <div className="inline-block mb-4">
              <span className="px-3 py-1 bg-primary/10 text-primary rounded-full text-sm font-semibold">
                {post.category}
              </span>
            </div>

            <h1 className="text-5xl md:text-6xl font-bold mb-6 leading-tight">
              {post.title}
            </h1>

            <div className="flex flex-col gap-4 text-muted-foreground">
              <div className="flex items-center gap-4 text-base">
                <span className="font-semibold text-foreground">{post.author}</span>
                <span>•</span>
                <div className="flex items-center gap-2">
                  <Calendar size={18} />
                  <span>{post.date}</span>
                </div>
                <span>•</span>
                <div className="flex items-center gap-2">
                  <Clock size={18} />
                  <span>{post.readTime}</span>
                </div>
              </div>
            </div>
          </div>

          {/* Article Content */}
          <div className="prose prose-lg dark:prose-invert max-w-none mb-16">
            <div className="bg-card rounded-3xl p-8 md:p-12 border border-border">
              <style>{`
                .prose h2 {
                  font-size: 2rem;
                  font-weight: 700;
                  margin-top: 2rem;
                  margin-bottom: 1rem;
                  color: var(--foreground);
                }

                .prose h3 {
                  font-size: 1.5rem;
                  font-weight: 600;
                  margin-top: 1.5rem;
                  margin-bottom: 0.75rem;
                  color: var(--foreground);
                }

                .prose p {
                  font-size: 1.125rem;
                  line-height: 1.75;
                  margin-bottom: 1.5rem;
                  color: var(--foreground);
                }

                .prose ul,
                .prose ol {
                  margin-left: 1.5rem;
                  margin-bottom: 1.5rem;
                }

                .prose li {
                  font-size: 1.125rem;
                  line-height: 1.75;
                  margin-bottom: 0.5rem;
                  color: var(--foreground);
                }

                .prose li strong {
                  color: var(--primary);
                  font-weight: 600;
                }

                .prose strong {
                  font-weight: 600;
                  color: var(--foreground);
                }
              `}</style>
              <div dangerouslySetInnerHTML={{ __html: post.content }} />
            </div>
          </div>

          {/* Author Bio */}
          <div className="bg-card rounded-3xl p-8 border border-border mb-16">
            <div className="flex gap-6 items-start">
              <div className="w-16 h-16 bg-primary/10 rounded-full flex items-center justify-center flex-shrink-0">
                <span className="text-2xl font-bold text-primary">T</span>
              </div>
              <div>
                <h3 className="text-xl font-bold mb-2">{post.author}</h3>
                <p className="text-muted-foreground">
                  Passionate developer and creator of Commit+. Focused on building beautiful and performant macOS applications.
                </p>
              </div>
            </div>
          </div>
        </article>

        {/* Navigation */}
        {(previousPost || nextPost) && (
          <div className="grid md:grid-cols-2 gap-6 mb-16">
            {previousPost ? (
              <Link
                href={`/blog/${previousPost.slug}`}
                className="bg-card rounded-3xl p-6 border border-border hover:border-primary transition group"
              >
                <div className="text-sm text-muted-foreground mb-2">← Previous</div>
                <h3 className="font-semibold group-hover:text-primary transition line-clamp-2">
                  {previousPost.title}
                </h3>
              </Link>
            ) : (
              <div />
            )}
            {nextPost ? (
              <Link
                href={`/blog/${nextPost.slug}`}
                className="bg-card rounded-3xl p-6 border border-border hover:border-primary transition group text-right"
              >
                <div className="text-sm text-muted-foreground mb-2">Next →</div>
                <h3 className="font-semibold group-hover:text-primary transition line-clamp-2">
                  {nextPost.title}
                </h3>
              </Link>
            ) : (
              <div />
            )}
          </div>
        )}

        {/* Related Posts */}
        <div className="mb-16">
          <h2 className="text-3xl font-bold mb-8">More from our blog</h2>
          <div className="grid md:grid-cols-2 gap-6">
            {blogPosts
              .filter(p => p.slug !== post.slug)
              .slice(0, 2)
              .map(relatedPost => (
                <Link
                  key={relatedPost.slug}
                  href={`/blog/${relatedPost.slug}`}
                  className="bg-card rounded-3xl p-6 border border-border hover:shadow-lg transition group"
                >
                  <div className="flex items-center gap-2 text-sm text-muted-foreground mb-3">
                    <Calendar size={16} />
                    <span>{relatedPost.date}</span>
                  </div>
                  <h3 className="text-lg font-bold mb-2 group-hover:text-primary transition">
                    {relatedPost.title}
                  </h3>
                  <p className="text-muted-foreground text-sm">{relatedPost.excerpt}</p>
                </Link>
              ))}
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="border-t border-border bg-secondary">
        <div className="max-w-6xl mx-auto px-6 py-12 text-center text-muted-foreground">
          <p>© 2026 Commit+. All rights reserved.</p>
        </div>
      </footer>
    </div>
  )
}
