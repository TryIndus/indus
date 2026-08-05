import { createRootRouteWithContext, createRoute, createRouter, Outlet, redirect } from '@tanstack/react-router'
import type { RouterHistory } from '@tanstack/react-router'
import type { AppContext } from './lib/context'
import { AppShell } from './components/AppShell'
import { AuthPage, CompanyPage, DashboardPage, PlaceholderPage, SearchPage } from './pages'

const rootRoute = createRootRouteWithContext<AppContext>()({ component: Outlet, notFoundComponent: () => <main className="grid min-h-screen place-items-center p-6 text-center"><div><p className="eyebrow">404</p><h1 className="mt-2 text-3xl font-semibold">Page not found</h1><a href="/dashboard" className="mt-5 inline-block text-sky-300">Return to dashboard</a></div></main> })
const authRoute = createRoute({ getParentRoute: () => rootRoute, path: '/auth', component: AuthPage, beforeLoad: async ({ context }) => { if (await context.auth.getUser()) throw redirect({ to: '/dashboard' }) } })
const protectedRoute = createRoute({ getParentRoute: () => rootRoute, id: '_protected', component: AppShell, beforeLoad: async ({ context, location }) => { if (!(await context.auth.getUser())) throw redirect({ to: '/auth', search: { redirect: location.href } }) } })
const dashboard = createRoute({ getParentRoute: () => protectedRoute, path: '/dashboard', component: DashboardPage })
const search = createRoute({ getParentRoute: () => protectedRoute, path: '/search', component: SearchPage })
const company = createRoute({ getParentRoute: () => protectedRoute, path: '/company/$symbol', component: CompanyPage })
const simple = (path: '/crypto' | '/favorites' | '/portfolios' | '/reports' | '/settings', kind: 'crypto' | 'favorites' | 'portfolios' | 'reports' | 'settings') => createRoute({ getParentRoute: () => protectedRoute, path, component: () => <PlaceholderPage kind={kind} /> })
const index = createRoute({ getParentRoute: () => rootRoute, path: '/', beforeLoad: () => { throw redirect({ to: '/dashboard' }) } })
const routeTree = rootRoute.addChildren([index, authRoute, protectedRoute.addChildren([dashboard, search, company, simple('/crypto', 'crypto'), simple('/favorites', 'favorites'), simple('/portfolios', 'portfolios'), simple('/reports', 'reports'), simple('/settings', 'settings')])])

export function makeRouter(context: AppContext, history?: RouterHistory) { return createRouter({ routeTree, context, history, defaultPreload: 'intent', scrollRestoration: true }) }
declare module '@tanstack/react-router' { interface Register { router: ReturnType<typeof makeRouter> } }
