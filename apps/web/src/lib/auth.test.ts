import { afterEach, describe, expect, it, vi } from 'vitest'
import { CognitoUser, CognitoUserPool } from 'amazon-cognito-identity-js'
import { createAuthAdapter } from './auth'

describe('authentication adapter selection', () => {
  afterEach(() => { vi.unstubAllEnvs(); vi.restoreAllMocks(); window.localStorage.clear() })

  function configuredAdapter() {
    vi.stubEnv('VITE_E2E_AUTH', 'false')
    vi.stubEnv('VITE_COGNITO_AUTHORITY', 'https://cognito-idp.us-east-1.amazonaws.com/us-east-1_example')
    vi.stubEnv('VITE_COGNITO_CLIENT_ID', 'example-client')
    return createAuthAdapter()
  }

  it('fails closed when identity configuration and the test flag are absent', async () => {
    vi.stubEnv('VITE_E2E_AUTH', 'false')
    vi.stubEnv('VITE_COGNITO_AUTHORITY', '')
    vi.stubEnv('VITE_COGNITO_CLIENT_ID', '')
    const auth = createAuthAdapter()
    expect(await auth.getUser()).toBeNull()
    expect(await auth.accessToken()).toBeNull()
    await expect(auth.passwordSignIn('user@example.test', 'Password123!Secure')).rejects.toThrow('Authentication is not configured')
  })

  it('requires both the build flag and explicit browser opt-in for test identity', async () => {
    vi.stubEnv('VITE_E2E_AUTH', 'true')
    const auth = createAuthAdapter()
    expect(await auth.getUser()).toBeNull()
    window.localStorage.setItem('indus:e2e-auth', 'true')
    expect(await auth.getUser()).toEqual({ id: 'e2e-user', email: 'investor@example.test' })
    expect(await auth.accessToken()).toBe('e2e-access-token')
  })

  it('supports the complete local E2E sign-in and sign-out lifecycle', async () => {
    vi.stubEnv('VITE_E2E_AUTH', 'true')
    const auth = createAuthAdapter()

    await auth.passwordSignIn('investor@example.test', 'Password123!Secure')
    expect(await auth.getUser()).toEqual({ id: 'e2e-user', email: 'investor@example.test' })
    expect(await auth.accessToken()).toBe('e2e-access-token')

    await auth.signOut()
    expect(await auth.getUser()).toBeNull()
    expect(await auth.accessToken()).toBeNull()
  })

  it('uses Cognito client flows for passwords, registration, and recovery', async () => {
    vi.spyOn(CognitoUser.prototype, 'authenticateUser').mockImplementation((_details, callbacks) => { callbacks.onSuccess({} as never); return undefined as never })
    vi.spyOn(CognitoUserPool.prototype, 'signUp').mockImplementation((_username, _password, _attributes, _validation, callback) => { callback?.(undefined, { userConfirmed: false } as never); return undefined as never })
    vi.spyOn(CognitoUser.prototype, 'confirmRegistration').mockImplementation((_code, _forceAlias, callback) => { callback(undefined, 'SUCCESS'); return undefined as never })
    vi.spyOn(CognitoUser.prototype, 'forgotPassword').mockImplementation(callbacks => { callbacks.inputVerificationCode?.({} as never); return undefined as never })
    vi.spyOn(CognitoUser.prototype, 'confirmPassword').mockImplementation((_code, _password, callbacks) => { callbacks.onSuccess('SUCCESS'); return undefined as never })

    const auth = configuredAdapter()
    await expect(auth.passwordSignIn?.('USER@EXAMPLE.TEST', 'password123')).resolves.toBeUndefined()
    await expect(auth.signUp?.('USER@EXAMPLE.TEST', 'password123', 'Avery', 'Investor')).resolves.toBe('confirmation-required')
    await expect(auth.confirmSignUp?.('USER@EXAMPLE.TEST', '123456')).resolves.toBeUndefined()
    await expect(auth.requestPasswordReset?.('USER@EXAMPLE.TEST')).resolves.toBeUndefined()
    await expect(auth.confirmPasswordReset?.('USER@EXAMPLE.TEST', '654321', 'newpassword123')).resolves.toBeUndefined()
  })

  it('reads and clears a valid Cognito password session', async () => {
    const signOut = vi.fn()
    const session = {
      isValid: () => true,
      getIdToken: () => ({ payload: { sub: 'user-1', email: 'user@example.test' } }),
      getAccessToken: () => ({ getJwtToken: () => 'access-token' }),
    }
    vi.spyOn(CognitoUserPool.prototype, 'getCurrentUser').mockReturnValue({
      getSession: (callback: (error: Error | null, value: typeof session) => void) => callback(null, session),
      signOut,
    } as never)
    const auth = configuredAdapter()
    await expect(auth.getUser()).resolves.toEqual({ id: 'user-1', email: 'user@example.test' })
    await expect(auth.accessToken()).resolves.toBe('access-token')
    await expect(auth.signOut()).resolves.toBe(false)
    expect(signOut).toHaveBeenCalled()
  })
})
