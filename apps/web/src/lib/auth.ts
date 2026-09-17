import { UserManager, WebStorageStateStore, type User } from 'oidc-client-ts'

export interface AuthUser {
  id: string
  email?: string
}

export interface AuthAdapter {
  getUser(): Promise<AuthUser | null>
  signIn(): Promise<void>
  completeSignIn(): Promise<void>
  signOut(): Promise<void>
  accessToken(): Promise<string | null>
}

class CognitoAuthAdapter implements AuthAdapter {
  private readonly manager: UserManager

  constructor(manager: UserManager) { this.manager = manager }

  private async activeUser(): Promise<User | null> {
    let user = await this.manager.getUser()
    if (user?.expired && user.refresh_token) {
      try {
        user = await this.manager.signinSilent()
      } catch {
        await this.manager.removeUser()
        return null
      }
    }
    return user && !user.expired ? user : null
  }

  async getUser() {
    const user = await this.activeUser()
    return user ? { id: user.profile.sub, email: user.profile.email } : null
  }

  async signIn() { await this.manager.signinRedirect() }
  async completeSignIn() { await this.manager.signinRedirectCallback() }
  async signOut() { await this.manager.signoutRedirect() }
  async accessToken() { return (await this.activeUser())?.access_token ?? null }
}

class UnconfiguredAuthAdapter implements AuthAdapter {
  async getUser() { return null }
  async signIn() { throw new Error('Authentication is not configured for this environment.') }
  async completeSignIn() { throw new Error('Authentication is not configured for this environment.') }
  async signOut() {}
  async accessToken() { return null }
}

const E2E_AUTH_KEY = 'indus:e2e-auth'
const browserStorage = () => globalThis.window?.localStorage

class E2eAuthAdapter implements AuthAdapter {
  async getUser() { return browserStorage()?.getItem(E2E_AUTH_KEY) === 'true' ? { id: 'e2e-user', email: 'investor@example.test' } : null }
  async signIn() { browserStorage()?.setItem(E2E_AUTH_KEY, 'true') }
  async completeSignIn() { browserStorage()?.setItem(E2E_AUTH_KEY, 'true') }
  async signOut() { browserStorage()?.removeItem(E2E_AUTH_KEY) }
  async accessToken() { return browserStorage()?.getItem(E2E_AUTH_KEY) === 'true' ? 'e2e-access-token' : null }
}

export function createAuthAdapter(): AuthAdapter {
  if (import.meta.env.VITE_E2E_AUTH === 'true') return new E2eAuthAdapter()

  const authority = import.meta.env.VITE_COGNITO_AUTHORITY
  const clientId = import.meta.env.VITE_COGNITO_CLIENT_ID
  if (!authority || !clientId || !globalThis.window) return new UnconfiguredAuthAdapter()

  const origin = window.location.origin
  return new CognitoAuthAdapter(new UserManager({
    authority,
    client_id: clientId,
    redirect_uri: import.meta.env.VITE_COGNITO_REDIRECT_URI || `${origin}/auth/callback`,
    post_logout_redirect_uri: import.meta.env.VITE_COGNITO_LOGOUT_URI || `${origin}/auth`,
    response_type: 'code',
    scope: 'openid email profile',
    userStore: new WebStorageStateStore({ store: window.sessionStorage }),
    stateStore: new WebStorageStateStore({ store: window.sessionStorage }),
    automaticSilentRenew: false,
  }))
}
