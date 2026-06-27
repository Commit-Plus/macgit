export const blogPosts = [
  {
    id: 'introducing-commit-plus',
    slug: 'introducing-commit-plus',
    title: 'Introducing Commit+: A Native Git Client for macOS',
    excerpt: 'We\'re excited to announce Commit+, a lightning-fast, native macOS Git client built with Swift and SwiftUI.',
    date: 'June 27, 2026',
    readTime: '5 min read',
    author: 'Thanh Tran',
    category: 'Announcement',
    image: '/logo.png',
    content: `
      <h2>Introducing Commit+: A Native Git Client for macOS</h2>
      
      <p>We're thrilled to announce the release of Commit+, a revolutionary native Git client for macOS that combines elegance, speed, and simplicity. Built from the ground up with Swift and SwiftUI, Commit+ represents our commitment to creating tools that developers actually love to use.</p>
      
      <h3>Why Another Git Client?</h3>
      
      <p>While there are many Git clients available, most web-based solutions lack the responsiveness and integration that macOS developers expect. Commit+ changes this by leveraging native technologies to deliver an unparalleled user experience.</p>
      
      <p>We spent months researching developer workflows and pain points. What emerged was a clear vision: a Git client that respects your Mac, integrates seamlessly with the system, and makes Git operations intuitive and enjoyable.</p>
      
      <h3>Key Features</h3>
      
      <ul>
        <li><strong>Lightning-Fast Performance:</strong> Native Swift implementation means instant responsiveness and minimal memory footprint.</li>
        <li><strong>Intuitive Drag & Drop:</strong> Perform complex Git operations with simple drag and drop gestures.</li>
        <li><strong>Beautiful Interface:</strong> iOS 26-inspired design with high corner rounding and smooth animations.</li>
        <li><strong>Powerful Features:</strong> Full Git management including branching, merging, rebasing, and conflict resolution.</li>
        <li><strong>Free & Open Source:</strong> Licensed under GNU Affero General Public License v3.0, available to everyone.</li>
      </ul>
      
      <h3>The Team Behind Commit+</h3>
      
      <p>Commit+ is developed by a passionate team of macOS developers who wanted to create the Git client they wished existed. Our commitment to open source means you can inspect the code, contribute improvements, and build on our work.</p>
      
      <h3>What's Next</h3>
      
      <p>This is just the beginning. We have an exciting roadmap ahead with AI-powered features, enhanced collaboration tools, and much more. Download Commit+ today and be part of the Git revolution for macOS.</p>
      
      <p>Thank you for being part of this journey. Happy committing!</p>
    `,
  },
  {
    id: 'drag-drop-git-operations',
    slug: 'drag-drop-git-operations',
    title: 'Drag & Drop Git Operations: A Game Changer',
    excerpt: 'Discover how drag and drop transforms complex Git operations into intuitive, visual interactions.',
    date: 'June 20, 2026',
    readTime: '7 min read',
    author: 'Thanh Tran',
    category: 'Features',
    image: '/logo.png',
    content: `
      <h2>Drag & Drop Git Operations: A Game Changer</h2>
      
      <p>One of Commit+'s standout features is its intuitive drag and drop interface for Git operations. But how did we arrive at this design decision, and why is it such a game changer for developers?</p>
      
      <h3>The Problem with Traditional Git Interfaces</h3>
      
      <p>Traditional Git clients rely heavily on menu systems, command palettes, and context menus. While powerful, these interfaces can feel disconnected from the data you're working with. When you want to move a commit to another branch, you often need to navigate through multiple dialogs and confirmations.</p>
      
      <p>We wanted to change this paradigm. Git operations should feel visual and direct, just like working with files on your Mac.</p>
      
      <h3>Our Solution: Drag & Drop Workflows</h3>
      
      <p>In Commit+, you can drag commits between branches, move files between staging areas, and reorder commits—all with intuitive drag and drop gestures. This creates a more tactile, direct connection between you and your repository.</p>
      
      <h3>Real-World Examples</h3>
      
      <ul>
        <li><strong>Moving Commits:</strong> Drag a commit from one branch to another to cherry-pick it instantly.</li>
        <li><strong>Stage & Unstage:</strong> Drag files between the working directory and staging area with visual feedback.</li>
        <li><strong>Reorder History:</strong> Rearrange commits visually before rebasing.</li>
        <li><strong>Merge Resolution:</strong> Drag to select which version of conflicted files to keep.</li>
      </ul>
      
      <h3>Developer Feedback</h3>
      
      <p>Early testers have been amazed by how much faster they complete Git workflows with drag and drop. Tasks that previously took 10+ seconds and multiple steps now take seconds with a simple drag gesture.</p>
      
      <h3>Looking Forward</h3>
      
      <p>We're constantly improving our drag and drop implementation based on developer feedback. Future versions will include even more sophisticated operations and smoother animations. Have an idea? Contribute it on GitHub!</p>
    `,
  },
  {
    id: 'why-native-apps-matter',
    slug: 'why-native-apps-matter',
    title: 'Why Native Apps Matter for Developer Tools',
    excerpt: 'Explore the benefits of native development: performance, memory efficiency, and seamless macOS integration.',
    date: 'June 13, 2026',
    readTime: '6 min read',
    author: 'Thanh Tran',
    category: 'Technical',
    image: '/logo.png',
    content: `
      <h2>Why Native Apps Matter for Developer Tools</h2>
      
      <p>In an era dominated by Electron apps and web technologies, why did we choose to build Commit+ as a native macOS application? This decision profoundly influences every aspect of our product, and we're excited to share our reasoning.</p>
      
      <h3>Performance is Non-Negotiable</h3>
      
      <p>Developer tools live in a special category. We use them constantly, sometimes hundreds of times per day. Even small delays accumulate into wasted hours. Commit+ opens instantly, responds immediately to every interaction, and runs with minimal CPU usage. These aren't luxuries—they're essentials for a tool you'll use all day.</p>
      
      <h3>Memory Efficiency</h3>
      
      <p>Electron apps running in a Chromium browser engine can easily consume 200-500MB of memory just to display a UI. Commit+, built with Swift and SwiftUI, uses a fraction of that. When you're running multiple development tools, this matters significantly.</p>
      
      <h3>Seamless macOS Integration</h3>
      
      <p>Native apps integrate beautifully with macOS. Commit+ respects system dark mode, uses native file pickers, integrates with Spotlight search, and follows Apple's Human Interface Guidelines. These details aren't optional—they create the smooth, unified experience that makes macOS special.</p>
      
      <h3>Safety and Security</h3>
      
      <p>As a developer tool that accesses your Git repositories, security is paramount. Native Swift code provides better control over memory safety and reduces the attack surface compared to JavaScript-based alternatives.</p>
      
      <h3>Future-Proofing</h3>
      
      <p>By building with native technologies, we ensure Commit+ remains compatible with future macOS releases. We directly benefit from Apple's investments in performance and capabilities, rather than waiting for web technologies to catch up.</p>
      
      <h3>The Trade-Off</h3>
      
      <p>Yes, native development is more complex than web technologies. It requires different expertise and longer development timelines. But for a tool you'll use daily, the investment pays dividends in user experience, performance, and reliability.</p>
      
      <h3>Conclusion</h3>
      
      <p>Commit+ demonstrates that native applications still have an important place in the developer tool ecosystem. By combining modern design sensibilities with native Swift development, we've created something that feels at home on the Mac while delivering the performance and integration developers demand.</p>
    `,
  },
]

export function getBlogPost(slug: string) {
  return blogPosts.find(post => post.slug === slug)
}

export function getAllBlogSlugs() {
  return blogPosts.map(post => ({ slug: post.slug }))
}
