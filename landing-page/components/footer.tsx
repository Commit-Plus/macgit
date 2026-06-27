import Link from 'next/link'
import { Code, Mail } from 'lucide-react'

export function Footer() {
  return (
    <footer className="bg-card border-t border-border">
      <div className="max-w-6xl mx-auto px-6 py-16">
        <div className="grid md:grid-cols-4 gap-12 mb-12">
          <div>
            <div className="flex items-center gap-2 mb-4">
              <div className="w-8 h-8 bg-primary rounded-2xl flex items-center justify-center text-white font-bold text-sm">
                C+
              </div>
              <span className="font-bold text-lg">Commit+</span>
            </div>
            <p className="text-muted-foreground text-sm">
              A fast, native Git client for macOS.
            </p>
          </div>

          <div>
            <h4 className="font-bold mb-4">Product</h4>
            <ul className="space-y-2 text-sm text-muted-foreground">
              <li>
                <Link href="#features" className="hover:text-foreground transition">
                  Features
                </Link>
              </li>
              <li>
                <Link href="#pricing" className="hover:text-foreground transition">
                  Pricing
                </Link>
              </li>
              <li>
                <Link href="#download" className="hover:text-foreground transition">
                  Download
                </Link>
              </li>
            </ul>
          </div>

          <div>
            <h4 className="font-bold mb-4">Resources</h4>
            <ul className="space-y-2 text-sm text-muted-foreground">
              <li>
                <Link href="#docs" className="hover:text-foreground transition">
                  Documentation
                </Link>
              </li>
              <li>
                <Link href="#blog" className="hover:text-foreground transition">
                  Blog
                </Link>
              </li>
              <li>
                <Link
                  href="https://github.com/Tranthanh98/macgit"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:text-foreground transition"
                >
                  GitHub
                </Link>
              </li>
            </ul>
          </div>

          <div>
            <h4 className="font-bold mb-4">Connect</h4>
            <div className="flex gap-4">
              <Link
                href="https://github.com/Tranthanh98/macgit"
                target="_blank"
                rel="noopener noreferrer"
                className="w-10 h-10 bg-secondary rounded-full flex items-center justify-center hover:bg-primary hover:text-primary-foreground transition"
                aria-label="GitHub"
              >
                <Code size={20} />
              </Link>
              <Link
                href="mailto:contact@commitplus.dev"
                className="w-10 h-10 bg-secondary rounded-full flex items-center justify-center hover:bg-primary hover:text-primary-foreground transition"
                aria-label="Email"
              >
                <Mail size={20} />
              </Link>
            </div>
          </div>
        </div>

        <div className="border-t border-border pt-8">
          <div className="flex flex-col md:flex-row justify-between items-center gap-4 text-sm text-muted-foreground">
            <p>© 2026 Commit+. All rights reserved.</p>
            <div className="flex gap-6">
              <Link href="#" className="hover:text-foreground transition">
                Privacy Policy
              </Link>
              <Link href="#" className="hover:text-foreground transition">
                Terms of Service
              </Link>
              <Link href="#" className="hover:text-foreground transition">
                License (AGPLv3)
              </Link>
            </div>
          </div>
        </div>
      </div>
    </footer>
  )
}
