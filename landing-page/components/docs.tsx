import { BookOpen, Code, Zap, HelpCircle, ArrowRight } from 'lucide-react'
import Link from 'next/link'

const docSections = [
  {
    icon: BookOpen,
    title: 'Getting Started',
    description: 'Learn how to install and set up Commit+ for the first time.',
    link: '#',
  },
  {
    icon: Code,
    title: 'Build from Source',
    description: 'Instructions for building Commit+ from the source code using Xcode.',
    link: '#',
  },
  {
    icon: Zap,
    title: 'Keyboard Shortcuts',
    description: 'Master Git operations with powerful keyboard shortcuts.',
    link: '#',
  },
  {
    icon: HelpCircle,
    title: 'FAQ',
    description: 'Common questions and troubleshooting for Commit+.',
    link: '#',
  },
]

export function Docs() {
  return (
    <section id="docs" className="py-20 px-6">
      <div className="max-w-6xl mx-auto">
        <div className="text-center mb-16">
          <h2 className="text-4xl md:text-5xl font-bold mb-4">Documentation</h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            Everything you need to know about using and developing Commit+
          </p>
        </div>

        <div className="grid md:grid-cols-2 gap-6 mb-12">
          {docSections.map((section, index) => {
            const Icon = section.icon
            return (
              <Link
                key={index}
                href={section.link}
                className="bg-card border border-border rounded-3xl p-8 hover:border-primary hover:shadow-lg transition group"
              >
                <div className="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center mb-4 group-hover:bg-primary/20 transition">
                  <Icon className="text-primary" size={24} />
                </div>
                <h3 className="text-xl font-bold mb-2 group-hover:text-primary transition">
                  {section.title}
                </h3>
                <p className="text-muted-foreground mb-4">{section.description}</p>
                <div className="flex items-center gap-2 text-primary font-semibold group-hover:gap-3 transition">
                  Learn more
                  <ArrowRight size={16} />
                </div>
              </Link>
            )
          })}
        </div>

        <div className="bg-primary rounded-3xl p-12 md:p-16">
          <div className="grid md:grid-cols-2 gap-12">
            <div>
              <h3 className="text-3xl font-bold text-primary-foreground mb-4">
                Explore the Source
              </h3>
              <p className="text-primary-foreground/80 mb-8">
                Commit+ is completely open source. Visit the GitHub repository to explore the code, 
                contribute improvements, and build from source.
              </p>
              <Link
                href="https://github.com/Tranthanh98/macgit"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-2 text-primary-foreground font-semibold hover:gap-3 transition"
              >
                View on GitHub
                <ArrowRight size={20} />
              </Link>
            </div>

            <div className="bg-primary-foreground/10 rounded-2xl p-6 backdrop-blur-sm">
              <h4 className="font-bold text-primary-foreground mb-4">Quick Stats</h4>
              <div className="space-y-3 text-primary-foreground/80 text-sm">
                <div className="flex justify-between">
                  <span>Language</span>
                  <span className="font-semibold">Swift 5.0</span>
                </div>
                <div className="flex justify-between">
                  <span>Framework</span>
                  <span className="font-semibold">SwiftUI</span>
                </div>
                <div className="flex justify-between">
                  <span>Dependencies</span>
                  <span className="font-semibold">0 (zero!)</span>
                </div>
                <div className="flex justify-between">
                  <span>Platform</span>
                  <span className="font-semibold">macOS 26.2+</span>
                </div>
                <div className="flex justify-between">
                  <span>License</span>
                  <span className="font-semibold">AGPLv3</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
