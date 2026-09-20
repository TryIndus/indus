import { AuthenticationDetails, CognitoUser, CognitoUserAttribute, CognitoUserPool, type CognitoUserSession } from 'amazon-cognito-identity-js'

export interface AuthUser {
  id: string
  email?: string
}

export interface AuthAdapter {
  getUser(): Promise<AuthUser | null>
  signOut(): Promise<boolean>
  accessToken(): Promise<string | null>
  passwordSignIn(email: string, password: string): Promise<void>
  signUp(email: string, password: string, firstName: string, lastName: string): Promise<'confirmed' | 'confirmation-required'>
  confirmSignUp(email: string, code: string): Promise<void>
  requestPasswordReset(email: string): Promise<void>
  confirmPasswordReset(email: string, code: string, password: string): Promise<void>
}

class CognitoAuthAdapter implements AuthAdapter {
  private readonly pool: CognitoUserPool

  constructor(pool: CognitoUserPool) { this.pool = pool }

  private passwordSession(): Promise<CognitoUserSession | null> {
    const user = this.pool.getCurrentUser()
    if (!user) return Promise.resolve(null)
    return new Promise(resolve => user.getSession((error: Error | null, session: CognitoUserSession | null) => resolve(error || !session?.isValid() ? null : session)))
  }

  async getUser() {
    const session = await this.passwordSession()
    if (!session) return null
    const payload = session.getIdToken().payload as { sub?: string; email?: string }
    return { id: payload.sub ?? '', email: payload.email }
  }

  async signOut() {
    this.pool.getCurrentUser()?.signOut()
    return false
  }
  async accessToken() { return (await this.passwordSession())?.getAccessToken().getJwtToken() ?? null }

  async passwordSignIn(email: string, password: string) {
    const user = new CognitoUser({ Username: email.trim().toLowerCase(), Pool: this.pool })
    const authentication = new AuthenticationDetails({ Username: email.trim().toLowerCase(), Password: password })
    await new Promise<void>((resolve, reject) => user.authenticateUser(authentication, {
      onSuccess: () => resolve(), onFailure: reject,
      newPasswordRequired: () => reject(new Error('A new password is required. Use account recovery to continue.')),
      mfaRequired: () => reject(new Error('Multi-factor authentication is still enabled for this account. Please try again after the Cognito configuration is updated.')),
      totpRequired: () => reject(new Error('Multi-factor authentication is still enabled for this account. Please try again after the Cognito configuration is updated.')),
      mfaSetup: () => reject(new Error('Multi-factor authentication is still enabled for this account. Please try again after the Cognito configuration is updated.')),
      selectMFAType: () => reject(new Error('Multi-factor authentication is still enabled for this account. Please try again after the Cognito configuration is updated.')),
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
  private unavailable(): never { throw new Error('Authentication is not configured for this environment.') }
  async getUser() { return null }
  async signOut() { return false }
  async accessToken() { return null }
  async passwordSignIn() { this.unavailable() }
  async signUp(): Promise<'confirmed' | 'confirmation-required'> { return this.unavailable() }
  async confirmSignUp() { this.unavailable() }
  async requestPasswordReset() { this.unavailable() }
  async confirmPasswordReset() { this.unavailable() }
}

const E2E_AUTH_KEY = 'indus:e2e-auth'
const browserStorage = () => globalThis.window?.localStorage

class E2eAuthAdapter implements AuthAdapter {
  async getUser() { return browserStorage()?.getItem(E2E_AUTH_KEY) === 'true' ? { id: 'e2e-user', email: 'investor@example.test' } : null }
  async signOut() { browserStorage()?.removeItem(E2E_AUTH_KEY); return false }
  async accessToken() { return browserStorage()?.getItem(E2E_AUTH_KEY) === 'true' ? 'e2e-access-token' : null }
  async passwordSignIn() { browserStorage()?.setItem(E2E_AUTH_KEY, 'true') }
  async signUp() { return 'confirmation-required' as const }
  async confirmSignUp() {}
  async requestPasswordReset() {}
  async confirmPasswordReset() {}
}

export function createAuthAdapter(): AuthAdapter {
  if (import.meta.env.VITE_E2E_AUTH === 'true') return new E2eAuthAdapter()

  const authority = import.meta.env.VITE_COGNITO_AUTHORITY
  const clientId = import.meta.env.VITE_COGNITO_CLIENT_ID
  if (!authority || !clientId || !globalThis.window) return new UnconfiguredAuthAdapter()

  const userPoolId = new URL(authority).pathname.replace(/^\//, '')
  const pool = new CognitoUserPool({ UserPoolId: userPoolId, ClientId: clientId })
  return new CognitoAuthAdapter(pool)
}
