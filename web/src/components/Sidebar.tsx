'use client'

import Link from "next/link"
import { usePathname, useRouter } from "next/navigation"
import { createClient } from "@/lib/supabase/client"
import type { User } from "@supabase/supabase-js"
import { ClipboardList, Home, LayoutDashboard, LogOut, Search, Sparkles } from "lucide-react"
import { ModeToggle } from "@/components/mode-toggle"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"

const navigation = [
  { name: "Dashboard", href: "/dashboard", icon: LayoutDashboard },
  { name: "Demo", href: "/dashboard/demo", icon: Sparkles, highlight: true },
  { name: "Workspaces", href: "/dashboard/workspaces", icon: Home },
  { name: "Search", href: "/dashboard/search", icon: Search },
  { name: "Proposals", href: "/dashboard/proposals", icon: ClipboardList },
]

export function Sidebar({ user }: { user: User }) {
  const pathname = usePathname()
  const router = useRouter()
  const supabase = createClient()

  const handleSignOut = async () => {
    await supabase.auth.signOut()
    router.push("/login")
  }

  return (
    <aside className="relative flex w-72 shrink-0 flex-col border-r border-border bg-card/60 backdrop-blur">
      <div className="flex items-center justify-between border-b border-border px-6 py-5">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-muted-foreground">
            Clearinghouse
          </p>
          <h1 className="text-xl font-bold leading-tight">IP Licensing</h1>
        </div>
        <ModeToggle />
      </div>

      <nav className="flex-1 space-y-1 px-4 py-4">
        {navigation.map((item) => {
          const isActive = pathname === item.href || pathname.startsWith(`${item.href}/`)
          const isHighlight = 'highlight' in item && item.highlight
          return (
            <Link
              key={item.name}
              href={item.href}
              className={cn(
                "group flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-colors",
                isActive
                  ? "bg-primary/10 text-primary"
                  : isHighlight
                    ? "text-primary/80 hover:bg-primary/5 hover:text-primary"
                    : "text-muted-foreground hover:bg-muted hover:text-foreground"
              )}
            >
              <item.icon
                className={cn(
                  "h-5 w-5",
                  isActive ? "text-primary" : isHighlight ? "text-primary/80" : "text-muted-foreground group-hover:text-foreground"
                )}
              />
              {item.name}
              {isHighlight && !isActive && (
                <span className="ml-auto text-[10px] font-semibold uppercase tracking-wide text-primary/60 bg-primary/10 px-1.5 py-0.5 rounded">
                  New
                </span>
              )}
            </Link>
          )
        })}
      </nav>

      <div className="border-t border-border px-4 py-4">
        <div className="flex items-center gap-3 rounded-xl bg-muted/60 p-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary/10 text-sm font-semibold text-primary">
            {user.email?.[0].toUpperCase()}
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-sm font-semibold text-foreground truncate">{user.email}</p>
            <p className="text-xs text-muted-foreground">Signed in</p>
          </div>
        </div>
        <Button
          variant="ghost"
          size="sm"
          className="mt-3 w-full justify-center gap-2 text-muted-foreground hover:text-foreground"
          onClick={handleSignOut}
        >
          <LogOut className="h-4 w-4" />
          Sign out
        </Button>
      </div>
    </aside>
  )
}
