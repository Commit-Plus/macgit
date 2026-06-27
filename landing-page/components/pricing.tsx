import { Check } from 'lucide-react'
import Link from 'next/link'

export function Pricing() {
  return (
    <section id="pricing" className="py-20 px-6">
      <div className="max-w-6xl mx-auto">
        <div className="text-center mb-16">
          <h2 className="text-4xl md:text-5xl font-bold mb-4">Simple pricing</h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            One plan that scales with your workflow. Forever free and open source.
          </p>
        </div>

        <div className="grid md:grid-cols-2 gap-8 max-w-2xl mx-auto">
          {/* Free Plan */}
          <div className="bg-card rounded-3xl p-8 border border-border relative">
            <div className="mb-8">
              <h3 className="text-2xl font-bold mb-2">Free</h3>
              <p className="text-muted-foreground">Everything you need</p>
            </div>

            <div className="mb-8">
              <div className="flex items-baseline gap-1">
                <span className="text-4xl font-bold">$0</span>
                <span className="text-muted-foreground">/month</span>
              </div>
              <p className="text-sm text-muted-foreground mt-2">Forever free. Open source.</p>
            </div>

            <Link
              href="#download"
              className="block w-full bg-primary text-primary-foreground px-6 py-3 rounded-2xl font-semibold text-center hover:opacity-90 transition mb-8"
            >
              Download Now
            </Link>

            <div className="space-y-4">
              <div className="flex gap-3">
                <Check className="text-primary flex-shrink-0" size={20} />
                <span>Native macOS app built with Swift</span>
              </div>
              <div className="flex gap-3">
                <Check className="text-primary flex-shrink-0" size={20} />
                <span>Drag & drop Git operations</span>
              </div>
              <div className="flex gap-3">
                <Check className="text-primary flex-shrink-0" size={20} />
                <span>Unlimited undo/redo</span>
              </div>
              <div className="flex gap-3">
                <Check className="text-primary flex-shrink-0" size={20} />
                <span>Full Git management suite</span>
              </div>
              <div className="flex gap-3">
                <Check className="text-primary flex-shrink-0" size={20} />
                <span>Conflict resolution</span>
              </div>
              <div className="flex gap-3">
                <Check className="text-primary flex-shrink-0" size={20} />
                <span>Worktree management</span>
              </div>
              <div className="flex gap-3">
                <Check className="text-primary flex-shrink-0" size={20} />
                <span>Quick search</span>
              </div>
              <div className="flex gap-3">
                <Check className="text-primary flex-shrink-0" size={20} />
                <span>Zero external dependencies</span>
              </div>
              <div className="flex gap-3">
                <Check className="text-primary flex-shrink-0" size={20} />
                <span>Open source (AGPLv3)</span>
              </div>
            </div>
          </div>

          {/* Pro Plan */}
          <div className="bg-primary text-primary-foreground rounded-3xl p-8 relative overflow-hidden">
            <div className="absolute top-4 right-4 bg-accent text-accent-foreground px-3 py-1 rounded-full text-sm font-semibold">
              Coming Soon
            </div>

            <div className="mb-8">
              <h3 className="text-2xl font-bold mb-2">Pro</h3>
              <p className="text-primary-foreground/80">Advanced AI features</p>
            </div>

            <div className="mb-8">
              <div className="flex items-baseline gap-1">
                <span className="text-4xl font-bold">TBD</span>
              </div>
              <p className="text-sm text-primary-foreground/80 mt-2">Pricing to be announced</p>
            </div>

            <button
              disabled
              className="block w-full bg-primary-foreground text-primary px-6 py-3 rounded-2xl font-semibold text-center opacity-50 mb-8 cursor-not-allowed"
            >
              Coming Soon
            </button>

            <div className="space-y-4">
              <div className="flex gap-3">
                <Check className="flex-shrink-0" size={20} />
                <span>Everything in Free</span>
              </div>
              <div className="flex gap-3">
                <Check className="flex-shrink-0" size={20} />
                <span>AI Commit Generation</span>
              </div>
              <div className="flex gap-3">
                <Check className="flex-shrink-0" size={20} />
                <span>AI Conflict Resolution</span>
              </div>
              <div className="flex gap-3">
                <Check className="flex-shrink-0" size={20} />
                <span>Advanced analytics</span>
              </div>
              <div className="flex gap-3">
                <Check className="flex-shrink-0" size={20} />
                <span>Priority support</span>
              </div>
            </div>
          </div>
        </div>

        <div className="text-center mt-16">
          <p className="text-muted-foreground">
            No credit card required. Download and start using Commit+ for free immediately.
          </p>
        </div>
      </div>
    </section>
  )
}
