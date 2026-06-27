import { ArrowRight, Calendar } from 'lucide-react'
import Link from 'next/link'
import { blogPosts } from '@/lib/blog-data'

export function Blog() {
  return (
    <section id="blog" className="py-20 px-6 bg-secondary">
      <div className="max-w-6xl mx-auto">
        <div className="flex items-center justify-between mb-16">
          <div>
            <h2 className="text-4xl md:text-5xl font-bold mb-4">Latest from our blog</h2>
            <p className="text-lg text-muted-foreground">
              Stories, updates, and insights from the Commit+ team
            </p>
          </div>
          <Link
            href="#blog"
            className="hidden md:flex items-center gap-2 text-primary font-semibold hover:gap-3 transition"
          >
            View all
            <ArrowRight size={20} />
          </Link>
        </div>

        <div className="grid md:grid-cols-3 gap-6 mb-8">
          {blogPosts.map((post, index) => (
            <Link
              key={index}
              href={`/blog/${post.slug}`}
              className="bg-card rounded-3xl p-8 hover:shadow-lg transition group"
            >
              <div className="flex items-center gap-2 text-sm text-muted-foreground mb-4">
                <Calendar size={16} />
                <span>{post.date}</span>
                <span>•</span>
                <span>{post.readTime}</span>
              </div>

              <h3 className="text-xl font-bold mb-3 group-hover:text-primary transition">
                {post.title}
              </h3>

              <p className="text-muted-foreground mb-6">{post.excerpt}</p>

              <div className="flex items-center gap-2 text-primary font-semibold group-hover:gap-3 transition">
                Read article
                <ArrowRight size={16} />
              </div>
            </Link>
          ))}
        </div>

        <div className="md:hidden text-center">
          <Link
            href="#blog"
            className="inline-flex items-center gap-2 text-primary font-semibold hover:gap-3 transition"
          >
            View all articles
            <ArrowRight size={20} />
          </Link>
        </div>
      </div>
    </section>
  )
}
