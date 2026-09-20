import { Link, Outlet, useRouter } from '@tanstack/react-router'
import { Bitcoin, ChartNoAxesCombined, FileText, Heart, HelpCircle, LogOut, Menu, Search, Settings, WalletCards, X } from 'lucide-react'
import { useState } from 'react'
import { useAppContext } from '../app-context'

const links = [
  ['/dashboard', 'Dashboard', ChartNoAxesCombined], ['/search', 'Search', Search], ['/crypto', 'Crypto', Bitcoin],
  ['/favorites', 'Favorites', Heart], ['/portfolios', 'Portfolios', WalletCards], ['/reports', 'Reports', FileText], ['/settings', 'Settings', Settings],
] as const

export function AppShell() {
	const [open, setOpen] = useState(false)
	const { auth } = useAppContext()
	const router = useRouter()
	const signOut = async () => { if (!(await auth.signOut())) await router.navigate({ to: '/auth' }) }
  return <div className="min-h-screen md:grid md:grid-cols-[16rem_1fr]">
    <a href="#main" className="fixed -top-20 left-4 z-50 rounded bg-primary px-4 py-2 text-primary-foreground focus:top-4">Skip to content</a>
    <header className="flex h-16 items-center justify-between border-b border-border/70 bg-background/85 px-5 backdrop-blur-xl md:hidden">
      <Brand /><button aria-label={open ? 'Close navigation' : 'Open navigation'} onClick={() => setOpen(!open)}>{open ? <X /> : <Menu />}</button>
    </header>
    <aside className={`${open ? 'flex' : 'hidden'} fixed inset-x-0 top-16 z-40 h-[calc(100vh-4rem)] flex-col border-r border-border/80 bg-card p-5 md:sticky md:top-0 md:flex md:h-screen`}>
      <div className="hidden md:block"><Brand /></div>
      <nav aria-label="Primary" className="mt-8 flex flex-1 flex-col gap-1">
        {links.map(([to, label, Icon]) => <Link key={to} to={to} onClick={() => setOpen(false)} className="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm text-muted-foreground transition hover:bg-accent/60 hover:text-foreground [&.active]:bg-accent [&.active]:text-accent-foreground"><Icon size={17} aria-hidden />{label}</Link>)}
      </nav>
      <div className="mb-3 border-t border-border/70 pt-4"><a href="mailto:support@tryindus.ca" className="flex items-center gap-3 rounded-lg px-3 py-2 text-sm text-muted-foreground hover:bg-accent/60 hover:text-foreground"><HelpCircle size={17}/>Get Help</a></div>
      <button onClick={signOut} className="flex items-center gap-3 rounded-lg px-3 py-2 text-left text-sm text-muted-foreground hover:bg-accent/60 hover:text-foreground"><LogOut size={17} />Sign out</button>
    </aside>
    <div className="min-w-0"><header className="sticky top-0 z-30 hidden h-16 items-center justify-between border-b border-border/60 bg-background/85 px-6 backdrop-blur-xl md:flex"><span className="text-sm text-muted-foreground">Financial intelligence</span><Link to="/search" className="flex items-center gap-2 rounded-full border border-border px-4 py-2 text-sm text-muted-foreground hover:text-foreground"><Search size={15}/>Search companies</Link></header><main id="main" className="min-w-0 p-5 md:p-8 lg:p-10"><Outlet /></main></div>
  </div>
}

function Brand() { return <Link to="/dashboard" className="inline-flex items-center gap-2.5 text-lg font-bold tracking-[-.04em]"><img src="/logo.svg" alt="" className="h-8 w-8"/>Indus</Link> }
