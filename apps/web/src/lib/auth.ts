import { UserManager, WebStorageStateStore, type User } from 'oidc-client-ts'
import { AuthenticationDetails, CognitoUser, CognitoUserAttribute, CognitoUserPool, type CognitoUserSession } from 'amazon-cognito-identity-js'

export interface AuthUser {
  id: string
  email?: string
}

export interface AuthAdapter {
  getUser(): Promise<AuthUser | null>
  signIn(): Promise<void>
  completeSignIn(): Promise<void>
  signOut(): Promise<boolean>
  accessToken(): Promise<string | null>
  passwordSignIn?(email: string, password: string): Promise<void>
  signUp?(email: string, password: string, firstName: string, lastName: string): Promise<'confirmed' | 'confirmation-required'>
  confirmSignUp?(email: string, code: string): Promise<void>
  requestPasswordReset?(email: string): Promise<void>
  confirmPasswordReset?(email: string, code: string, password: string): Promise<void>
}

class CognitoAuthAdapter implements AuthAdapter {
  private readonly manager: UserManager
  private readonly pool: CognitoUserPool

  constructor(manager: UserManager, pool: CognitoUserPool) { this.manager = manager; this.pool = pool }

  private passwordSession(): Promise<CognitoUserSession | null> {
    const user = this.pool.getCurrentUser()
    if (!user) return Promise.resolve(null)
    return new Promise(resolve => user.getSession((error: Error | null, session: CognitoUserSession | null) => resolve(error || !session?.isValid() ? null : session)))
  }

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
    const session = await this.passwordSession()
    if (session) {
      const payload = session.getIdToken().payload as { sub?: string; email?: string }
      return { id: payload.sub ?? '', email: payload.email }
    }
    const user = await this.activeUser()
    return user ? { id: user.profile.sub, email: user.profile.email } : null
  }

  async signIn() { await this.manager.signinRedirect() }
  async completeSignIn() { await this.manager.signinRedirectCallback() }
  async signOut() {
    const passwordUser = this.pool.getCurrentUser()
    if (passwordUser) { passwordUser.signOut(); await this.manager.removeUser(); return false }
    await this.manager.signoutRedirect(); return true
  }
  async accessToken() { return (await this.passwordSession())?.getAccessToken().getJwtToken() ?? (await this.activeUser())?.access_token ?? null }

  async passwordSignIn(email: string, password: string) {
    const user = new CognitoUser({ Username: email.trim().toLowerCase(), Pool: this.pool })
    const authentication = new AuthenticationDetails({ Username: email.trim().toLowerCase(), Password: password })
    await new Promise<void>((resolve, reject) => user.authenticateUser(authentication, {
      onSuccess: () => resolve(), onFailure: reject,
      newPasswordRequired: () => reject(new Error('A new password is required. Use account recovery to continue.')),
      mfaRequired: () => reject(new Error('This account requires an MFA challenge that is not yet supported in this form.')),
      totpRequired: () => reject(new Error('This account requires an authenticator code that is not yet supported in this form.')),
    }))
  }

  async signUp(email: string, password: string, firstName: string, lastName: string) {
    const attributes = [new CognitoUserAttribute({ Name: 'given_name', Value: firstName }), new CognitoUserAttribute({ Name: 'family_name', Value: lastName }), new CognitoUserAttribute({ Name: 'name', Value: `${firstName} ${lastName}`.trim() })]
    return new Promise<'confirmed' | 'confirmation-required'>((resolve, reject) => this.pool.signUp(email.trim().toLowerCase(), password, attributes, [], (error, result) => error ? reject(error) : resolve(result?.userConfirmed ? 'confirmed' : 'confirmation-required')))
  }

  async confirmSignUp(email: string, code: string) {
    const user = new CognitoUser({ Username: email.trim().toLowerCase(), Pool: this.pool })
    await new Promise<void>((resolve, reject) => user.confirmRegistration(code.trim(), true, error => error ? reject(error) : resolve()))
  }

  async requestPasswordReset(email: string) {
    const user = new CognitoUser({ Username: email.trim().toLowerCase(), Pool: this.pool })
    await new Promise<void>((resolve, reject) => user.forgotPassword({ onSuccess: () => resolve(), onFailure: reject, inputVerificationCode: () => resolve() }))
  }

  async confirmPasswordReset(email: string, code: string, password: string) {
    const user = new CognitoUser({ Username: email.trim().toLowerCase(), Pool: this.pool })
    await new Promise<void>((resolve, reject) => user.confirmPassword(code.trim(), password, { onSuccess: () => resolve(), onFailure: reject }))
  }
}

class UnconfiguredAuthAdapter implements AuthAdapter {
  async getUser() { return null }
  async signIn() { throw new Error('Authentication is not configured for this environment.') }
  async completeSignIn() { throw new Error('Authentication is not configured for this environment.') }
  async signOut() { return false }
  async accessToken() { return null }
}

const E2E_AUTH_KEY = 'indus:e2e-auth'
const browserStorage = () => globalThis.window?.localStorage

class E2eAuthAdapter implements AuthAdapter {
  async getUser() { return browserStorage()?.getItem(E2E_AUTH_KEY) === 'true' ? { id: 'e2e-user', email: 'investor@example.test' } : null }
  async signIn() { browserStorage()?.setItem(E2E_AUTH_KEY, 'true') }
  async completeSignIn() { browserStorage()?.setItem(E2E_AUTH_KEY, 'true') }
  async signOut() { browserStorage()?.removeItem(E2E_AUTH_KEY); return false }
  async accessToken() { return browserStorage()?.getItem(E2E_AUTH_KEY) === 'true' ? 'e2e-access-token' : null }
}

export function createAuthAdapter(): AuthAdapter {
  if (import.meta.env.VITE_E2E_AUTH === 'true') return new E2eAuthAdapter()

  const authority = import.meta.env.VITE_COGNITO_AUTHORITY
  const clientId = import.meta.env.VITE_COGNITO_CLIENT_ID
  if (!authority || !clientId || !globalThis.window) return new UnconfiguredAuthAdapter()

  const origin = window.location.origin
  const userPoolId = new URL(authority).pathname.replace(/^\//, '')
  const pool = new CognitoUserPool({ UserPoolId: userPoolId, ClientId: clientId })
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
  }), pool)
}
