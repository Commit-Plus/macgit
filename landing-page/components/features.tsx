import { 
  Zap, 
  Undo2, 
  GitBranch, 
  Shield, 
  Search, 
  Layers,
  ArrowRight
} from 'lucide-react'

const features = [
  {
    icon: Zap,
    title: 'Drag & Drop',
    description: 'Reorder commits, cherry-pick, merge, push—all with intuitive drag and drop interactions.',
  },
  {
    icon: Undo2,
    title: 'Undo Any Action',
    description: 'Tower-style undo/redo for commits, stashes, branches, discards, and remote operations.',
  },
  {
    icon: GitBranch,
    title: 'Full Git Management',
    description: 'Commit, Pull, Push, Fetch, Branch, Merge, Rebase, Stash, Cherry-pick, Revert—all integrated.',
  },
  {
    icon: Shield,
    title: 'Conflict Resolution',
    description: 'Built-in visual diff viewer with inline conflict markers and stage resolution.',
  },
  {
    icon: Layers,
    title: 'Worktree Management',
    description: 'Create, switch, and manage git worktrees visually for parallel feature development.',
  },
  {
    icon: Search,
    title: 'Quick Search',
    description: 'Spotlight-style search modal to instantly find commits, files, branches, and tags.',
  },
]

export function Features() {
  return (
    <section id="features" className="py-20 px-6 bg-secondary">
      <div className="max-w-6xl mx-auto">
        <div className="text-center mb-16">
          <h2 className="text-4xl md:text-5xl font-bold mb-4">Powerful features</h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            Everything you need for professional Git workflows, right at your fingertips.
          </p>
        </div>

        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
          {features.map((feature, index) => {
            const Icon = feature.icon
            return (
              <div
                key={index}
                className="bg-card rounded-3xl p-8 hover:shadow-lg transition"
              >
                <div className="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center mb-4">
                  <Icon className="text-primary" size={24} />
                </div>
                <h3 className="text-xl font-bold mb-2">{feature.title}</h3>
                <p className="text-muted-foreground">{feature.description}</p>
              </div>
            )
          })}
        </div>

        <div className="mt-16 bg-primary rounded-3xl p-12 text-center">
          <h3 className="text-2xl font-bold text-primary-foreground mb-4">
            AI Features Coming Soon
          </h3>
          <p className="text-primary-foreground/80 max-w-2xl mx-auto mb-6">
            Auto-generate commit messages from your staged diff and get smart suggestions for resolving merge conflicts.
          </p>
          <div className="inline-flex items-center gap-2 text-primary-foreground font-medium">
            Powered by AI <ArrowRight size={20} />
          </div>
        </div>
      </div>
    </section>
  )
}
