import { ArrowLeft, ArrowRight, Eye, EyeOff, Loader2, Lock, Mail, ShieldCheck } from 'lucide-react'
import { useEffect, useRef, useState, type FormEvent } from 'react'
import { useNavigate } from '@tanstack/react-router'
import { useAppContext } from '../app-context'

type Mode = 'signin' | 'signup' | 'confirm' | 'forgot' | 'reset'
type PendingMode = Extract<Mode, 'confirm' | 'reset'>

const PENDING_FLOW_KEY = 'indus:pending-auth-flow'
const RESEND_UNTIL_KEY = 'indus:auth-resend-until'

function readPendingFlow(): { mode: PendingMode; email: string } | null {
  try {
    const value = JSON.parse(sessionStorage.getItem(PENDING_FLOW_KEY) ?? 'null') as { mode?: string; email?: string } | null
    return value && (value.mode === 'confirm' || value.mode === 'reset') && typeof value.email === 'string'
      ? { mode: value.mode, email: value.email }
      : null
  } catch { return null }
}

function readResendUntil(): number {
  try {
    const value = Number(sessionStorage.getItem(RESEND_UNTIL_KEY))
    return Number.isFinite(value) && value > Date.now() ? value : 0
  } catch { return 0 }
}

function rememberPendingFlow(mode: PendingMode | null, email: string): void {
  try {
    if (mode && email.trim()) sessionStorage.setItem(PENDING_FLOW_KEY, JSON.stringify({ mode, email: email.trim() }))
    else sessionStorage.removeItem(PENDING_FLOW_KEY)
  } catch { /* Session storage is optional; the current form still works. */ }
}

function authErrorMessage(cause: unknown, mode: Mode): string {
  const error = cause as { name?: string; code?: string } | null
  switch (error?.name ?? error?.code) {
    case 'CodeMismatchException': return 'That code is incorrect. Check the email and try again.'
    case 'ExpiredCodeException': return 'That code has expired. Send a new code below.'
    case 'LimitExceededException':
    case 'TooManyRequestsException': return 'Too many attempts. Wait a little before trying again.'
    case 'UsernameExistsException': return 'An account already uses this email. Sign in or confirm your email instead.'
    case 'InvalidPasswordException': return 'Use at least 14 characters with uppercase, lowercase, a number, and a symbol.'
    case 'NotAuthorizedException':
      if (mode === 'confirm') return 'This account may already be confirmed. Try signing in.'
      if (mode === 'reset') return 'This code may have already been used. Request a new code or try signing in.'
      if (mode === 'forgot') return 'We could not start recovery for this email. Check the address or try confirming your account.'
      return 'The email or password is incorrect. Try again or reset your password.'
    case 'InvalidParameterException': return mode === 'forgot'
      ? 'We could not start recovery. If your account is unconfirmed, choose “Confirm your email” from sign in.'
      : 'Check the information you entered and try again.'
    case 'NetworkError':
    case 'NetworkingError': return 'We could not reach the sign-in service. Check your connection and try again.'
    default: return mode === 'signin'
      ? 'We could not sign you in. Check your details and try again.'
      : 'We could not complete that request. Try again.'
  }
}

export function AuthPage() {
  const { auth } = useAppContext()
  const navigate = useNavigate()
  const [initialFlow] = useState(readPendingFlow)
  const [mode, setMode] = useState<Mode>(initialFlow?.mode ?? 'signin')
  const [email, setEmail] = useState(initialFlow?.email ?? '')
  const [password, setPassword] = useState('')
  const [firstName, setFirstName] = useState('')
  const [lastName, setLastName] = useState('')
  const [code, setCode] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const [resendUntil, setResendUntil] = useState(readResendUntil)
  const [now, setNow] = useState(Date.now)
  const resendSeconds = Math.max(0, Math.ceil((resendUntil - now) / 1000))
  const busyRef = useRef(false)
  const codeInput = useRef<HTMLInputElement>(null)
  const emailInput = useRef<HTMLInputElement>(null)
  const previousMode = useRef<Mode | null>(null)

  useEffect(() => {
    if (previousMode.current === mode) return
    previousMode.current = mode
    if (mode === 'confirm' || mode === 'reset') {
      if (email.trim()) codeInput.current?.focus()
      else emailInput.current?.focus()
    }
  }, [mode, email])

  useEffect(() => {
    rememberPendingFlow(mode === 'confirm' || mode === 'reset' ? mode : null, email)
  }, [mode, email])

  useEffect(() => {
    if (resendUntil <= Date.now()) return
    const refresh = () => setNow(Date.now())
    const timer = window.setInterval(refresh, 1000)
    document.addEventListener('visibilitychange', refresh)
    return () => { window.clearInterval(timer); document.removeEventListener('visibilitychange', refresh) }
  }, [resendUntil])

  const startCooldown = () => {
    const until = Date.now() + 30_000
    try { sessionStorage.setItem(RESEND_UNTIL_KEY, String(until)) } catch { /* The in-memory cooldown still applies. */ }
    setResendUntil(until)
    setNow(Date.now())
  }

  const changeMode = (next: Mode) => {
    if (busyRef.current) return
    setMode(next); setError(''); setMessage(''); setCode('')
    if (next !== 'confirm') setPassword('')
  }

  const perform = async (action: () => Promise<void>) => {
    if (busyRef.current) return
    busyRef.current = true
    setBusy(true); setError(''); setMessage('')
    try { await action() } catch (cause) {
      const cognitoError = cause as { name?: string; code?: string } | null
      if (cognitoError?.name === 'UserNotConfirmedException' || cognitoError?.code === 'UserNotConfirmedException') {
        setMode('confirm'); setCode(''); setMessage('Confirm your email to finish setting up your account.')
      } else setError(authErrorMessage(cause, mode))
    } finally { busyRef.current = false; setBusy(false) }
  }

  const finishSignIn = async () => {
    await auth.passwordSignIn(email, password)
    setPassword('')
    rememberPendingFlow(null, email)
    await navigate({ to: '/dashboard', replace: true })
  }

  const resendCode = () => {
    if (busyRef.current || Date.now() < resendUntil) return
    if (!emailInput.current?.reportValidity()) return
    void perform(async () => {
      if (mode === 'reset') await auth.requestPasswordReset(email)
      else await auth.resendConfirmationCode(email)
      startCooldown()
      setMessage('If this email can receive a code, check its inbox and spam folder.')
    })
  }

  const submit = (event: FormEvent) => {
    event.preventDefault()
    void perform(async () => {
      if (mode === 'signin') { await finishSignIn(); return }
      if (mode === 'signup') {
        const result = await auth.signUp(email, password, firstName, lastName)
        if (result === 'confirmation-required') {
          setMode('confirm'); setCode(''); startCooldown()
          setMessage('We sent a code to your email. Enter it here to continue.')
        } else {
          try { await finishSignIn() } catch { setMode('signin'); setMessage('Account created. Sign in to continue.') }
        }
        return
      }
      if (mode === 'confirm') {
        await auth.confirmSignUp(email, code)
        setCode('')
        if (password) {
          try { await finishSignIn(); return } catch { /* Confirmation succeeded; ask for sign-in again. */ }
        }
        setMode('signin'); setMessage('Email confirmed. Sign in to continue.')
        return
      }
      if (mode === 'forgot') { await auth.requestPasswordReset(email); setMode('reset'); startCooldown(); setMessage('If this account can receive a recovery code, check its email and enter the code here.'); return }
      await auth.confirmPasswordReset(email, code, password)
      try { await finishSignIn() } catch { setMode('signin'); setMessage('Password updated. Sign in to continue.') }
    })
  }

  const heading = mode === 'signup' ? 'Start your research.' : mode === 'confirm' ? 'Confirm your account.' : mode === 'forgot' || mode === 'reset' ? 'Recover your account.' : 'Continue your research.'
  const eyebrow = mode === 'signup' ? 'Create workspace' : mode === 'signin' ? 'Welcome back' : 'Secure account'
  const button = mode === 'signup' ? 'Create account' : mode === 'confirm' ? 'Confirm account' : mode === 'forgot' ? 'Send recovery code' : mode === 'reset' ? 'Set new password' : 'Sign in'

  return <div className="auth-layout">
    <section className="auth-summary" aria-label="Indus product summary"><div className="landing-grid absolute inset-0 opacity-70" /><div className="auth-glow" /><a href="/" className="brand-link relative z-10"><img src="/logo.svg" alt="" />Indus</a><div className="auth-summary-copy"><h1>Research companies.<br/><em>Keep the data together.</em></h1><p>Save companies, generate reports, and revisit your research.</p><span><ShieldCheck />Provider credentials and model prompts stay server-side.</span></div><p className="auth-stamp">INDUS / FINANCIAL INTELLIGENCE</p></section>
    <main className="auth-main"><div className="auth-form-wrap"><div className="mobile-auth-brand"><a href="/" className="brand-link"><img src="/logo.svg" alt="" />Indus</a><a href="/"><ArrowLeft />Home</a></div><p className="auth-eyebrow">{eyebrow}</p><h2>{heading}</h2><p className="auth-intro">{mode === 'signup' ? 'Create an account to save companies and generated research.' : mode === 'signin' ? 'Sign in to return to your watchlist, reports, and company analysis.' : mode === 'confirm' ? email ? <>Enter the code sent to <strong>{email}</strong>.</> : 'Enter your email and verification code, or request a new one below.' : 'Use the email associated with your Indus account.'}</p>
      <form onSubmit={submit} className="auth-form">
        {mode === 'signup' && <div className="name-grid"><label>First name<input value={firstName} onChange={e => setFirstName(e.target.value)} required autoComplete="given-name" /></label><label>Last name<input value={lastName} onChange={e => setLastName(e.target.value)} required autoComplete="family-name" /></label></div>}
        <label>Email<div className="input-wrap"><Mail/><input ref={emailInput} name="email" type="email" value={email} onChange={e => setEmail(e.target.value)} required autoComplete="email" placeholder="you@example.com" /></div></label>
        {(mode === 'signin' || mode === 'signup' || mode === 'reset') && <label>Password<div className="input-wrap"><Lock/><input name="password" type={showPassword ? 'text' : 'password'} value={password} onChange={e => setPassword(e.target.value)} required minLength={mode === 'signin' ? 1 : 14} autoComplete={mode === 'signin' ? 'current-password' : 'new-password'} placeholder="Password"/><button type="button" onClick={() => setShowPassword(value => !value)} aria-label={showPassword ? 'Hide password' : 'Show password'}>{showPassword ? <EyeOff/> : <Eye/>}</button></div>{mode !== 'signin' && <span className="auth-password-help">Use at least 14 characters with uppercase, lowercase, a number, and a symbol.</span>}</label>}
        {(mode === 'confirm' || mode === 'reset') && <label>Verification code<input ref={codeInput} name="verificationCode" className="plain-input auth-code-input" value={code} onChange={e => setCode(e.target.value)} required inputMode="numeric" autoComplete="one-time-code" placeholder="Enter code" /></label>}
        {error && <p role="alert" className="auth-error">{error}</p>}{message && <p role="status" className="auth-message">{message}</p>}
        <button className="auth-submit" disabled={busy}>{busy ? <><Loader2 className="animate-spin" aria-hidden="true"/>{mode === 'signup' ? 'Creating account...' : mode === 'confirm' ? 'Confirming...' : mode === 'forgot' ? 'Sending code...' : mode === 'reset' ? 'Updating password...' : 'Signing in...'}</> : <>{button}<ArrowRight aria-hidden="true"/></>}</button>
      </form>
      <div className="auth-actions">{mode === 'signin' ? <><button type="button" disabled={busy} onClick={() => changeMode('forgot')}>Forgot password?</button><p>New to Indus? <button type="button" disabled={busy} onClick={() => changeMode('signup')}>Create an account</button></p><p>Still waiting to verify? <button type="button" disabled={busy} onClick={() => changeMode('confirm')}>Confirm your email</button></p></> : <>{(mode === 'confirm' || mode === 'reset') && <p>Didn't get the code? <button type="button" onClick={resendCode} disabled={busy || resendSeconds > 0}>{resendSeconds > 0 ? `Resend in ${resendSeconds}s` : 'Send a new code'}</button></p>}<button type="button" disabled={busy} onClick={() => changeMode('signin')}>Back to sign in</button></>}</div>
    </div></main>
  </div>
}
