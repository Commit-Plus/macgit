import { ArrowRight } from 'lucide-react'
import Link from 'next/link'

export function Hero() {
  return (
    <section className="pt-32 pb-20 px-6 text-center">
      <div className="max-w-4xl mx-auto">
        <div className="inline-block mb-6 px-4 py-2 bg-secondary rounded-full">
          <p className="text-sm font-medium text-secondary-foreground">Native. Lightweight. Open Source.</p>
        </div>

        <h1 className="text-5xl md:text-7xl font-bold tracking-tight mb-6 leading-tight">
          The Git client <br />
          <span className="text-primary">macOS deserves</span>
        </h1>

        <p className="text-xl text-muted-foreground mb-8 max-w-2xl mx-auto leading-relaxed">
          Commit+ is a fast, native Git client built with Swift and SwiftUI. Zero external dependencies. 
          Drag and drop. Undo any action. Free and open source.
        </p>

        <div className="flex flex-col sm:flex-row gap-4 justify-center mb-16">
          <Link
            href="#download"
            className="bg-primary text-primary-foreground px-8 py-4 rounded-2xl font-semibold hover:opacity-90 transition inline-flex items-center justify-center gap-2 group"
          >
            Download for Free
            <ArrowRight size={20} className="group-hover:translate-x-1 transition" />
          </Link>

          <Link
            href="#features"
            className="border border-border bg-card text-foreground px-8 py-4 rounded-2xl font-semibold hover:bg-secondary transition"
          >
            View Features
          </Link>
        </div>

        <p className="text-sm text-muted-foreground">
          macOS 26.2+  •  Swift  •  SwiftUI  •  No dependencies
        </p>
      </div>
    </section>
  )
}
