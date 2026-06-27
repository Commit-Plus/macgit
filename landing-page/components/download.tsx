import { Download as DownloadIcon, Apple, Code } from 'lucide-react'
import Link from 'next/link'

export function Download() {
  return (
    <section id="download" className="py-20 px-6">
      <div className="max-w-4xl mx-auto">
        <div className="text-center mb-16">
          <h2 className="text-4xl md:text-5xl font-bold mb-4">Get Started</h2>
          <p className="text-lg text-muted-foreground">
            Download Commit+ or build from source
          </p>
        </div>

        <div className="grid md:grid-cols-2 gap-8">
          {/* Download */}
          <div className="bg-card border border-border rounded-3xl p-8 hover:border-primary hover:shadow-lg transition">
            <div className="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center mb-6">
              <DownloadIcon className="text-primary" size={24} />
            </div>

            <h3 className="text-2xl font-bold mb-2">Download</h3>
            <p className="text-muted-foreground mb-8">
              Get the latest release directly from GitHub
            </p>

            <Link
              href="https://github.com/Tranthanh98/macgit/releases"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-block w-full bg-primary text-primary-foreground px-6 py-3 rounded-2xl font-semibold text-center hover:opacity-90 transition mb-4"
            >
              Download Latest Release
            </Link>

            <div className="space-y-3 text-sm text-muted-foreground">
              <div className="flex items-start gap-2">
                <Apple size={16} className="flex-shrink-0 mt-0.5 text-primary" />
                <span>macOS 26.2 and later</span>
              </div>
              <div className="flex items-start gap-2">
                <Apple size={16} className="flex-shrink-0 mt-0.5 text-primary" />
                <span>Universal binary (Intel & Apple Silicon)</span>
              </div>
              <div className="flex items-start gap-2">
                <Apple size={16} className="flex-shrink-0 mt-0.5 text-primary" />
                <span>Notarized and signed</span>
              </div>
            </div>
          </div>

          {/* Build from Source */}
          <div className="bg-card border border-border rounded-3xl p-8 hover:border-primary hover:shadow-lg transition">
            <div className="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center mb-6">
              <Code className="text-primary" size={24} />
            </div>

            <h3 className="text-2xl font-bold mb-2">Build from Source</h3>
            <p className="text-muted-foreground mb-8">
              Clone the repository and build with Xcode
            </p>

            <Link
              href="https://github.com/Tranthanh98/macgit"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-block w-full bg-secondary text-foreground px-6 py-3 rounded-2xl font-semibold text-center hover:opacity-90 transition mb-4"
            >
              View Repository
            </Link>

            <div className="bg-muted rounded-xl p-4 text-sm font-mono text-foreground/80 overflow-x-auto">
              <code>{`git clone https://github.com/\nTranthanh98/macgit\ncd macgit\nxcodebuild -project macgit.\nxcodeproj -scheme macgit\n-configuration Release`}</code>
            </div>
          </div>
        </div>

        <div className="mt-16 text-center">
          <div className="inline-block bg-secondary rounded-3xl p-8">
            <p className="text-sm font-semibold text-primary mb-3">SYSTEM REQUIREMENTS</p>
            <div className="space-y-2 text-muted-foreground">
              <p>✓ macOS 26.2 or later</p>
              <p>✓ Git (Homebrew or Xcode Command Line Tools)</p>
              <p>✓ Apple Silicon or Intel processor</p>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
