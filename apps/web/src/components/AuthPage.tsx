import { ArrowLeft, ArrowRight, Eye, EyeOff, Loader2, Lock, Mail, ShieldCheck } from 'lucide-react'
import { useState, type FormEvent } from 'react'
import { useNavigate } from '@tanstack/react-router'
import { useAppContext } from '../app-context'

type Mode = 'signin' | 'signup' | 'confirm' | 'forgot' | 'reset'

export function AuthPage() {
  const { auth } = useAppContext()
  const navigate = useNavigate()
  const [mode, setMode] = useState<Mode>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [firstName, setFirstName] = useState('')
  const [lastName, setLastName] = useState('')
  const [code, setCode] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')

  const perform = async (action: () => Promise<void>) => {
    setBusy(true); setError(''); setMessage('')
    try { await action() } catch (cause) { setError(cause instanceof Error ? cause.message : 'We could not complete that request.') } finally { setBusy(false) }
  }

  const submit = (event: FormEvent) => {
    event.preventDefault()
    void perform(async () => {
      if (mode === 'signin') { await auth.passwordSignIn(email, password); await navigate({ to: '/dashboard', replace: true }); return }
      if (mode === 'signup') { const result = await auth.signUp(email, password, firstName, lastName); if (result === 'confirmation-required') { setMode('confirm'); setMessage('Enter the verification code sent to your email.') } else setMode('signin'); return }
      if (mode === 'confirm') { await auth.confirmSignUp(email, code); setMode('signin'); setMessage('Account confirmed. You can now sign in.'); return }
      if (mode === 'forgot') { await auth.requestPasswordReset(email); setMode('reset'); setMessage('Enter the recovery code sent to your email.'); return }
      await auth.confirmPasswordReset(email, code, password); setMode('signin'); setMessage('Password updated. You can now sign in.')
    })
  }

  const heading = mode === 'signup' ? 'Start your research.' : mode === 'confirm' ? 'Confirm your account.' : mode === 'forgot' || mode === 'reset' ? 'Recover your account.' : 'Continue your research.'
  const eyebrow = mode === 'signup' ? 'Create workspace' : mode === 'signin' ? 'Welcome back' : 'Secure account'
  const button = mode === 'signup' ? 'Create account' : mode === 'confirm' ? 'Confirm account' : mode === 'forgot' ? 'Send recovery code' : mode === 'reset' ? 'Set new password' : 'Sign in'

  return <div className="auth-layout">
    <section className="auth-summary" aria-label="Indus product summary"><div className="landing-grid absolute inset-0 opacity-70" /><div className="auth-glow" /><a href="/" className="brand-link relative z-10"><img src="/logo.svg" alt="" />Indus</a><div className="auth-summary-copy"><h1>Research companies.<br/><em>Keep the data together.</em></h1><p>Save companies, generate reports, and revisit your research.</p><span><ShieldCheck />Provider credentials and model prompts stay server-side.</span></div><p className="auth-stamp">INDUS / FINANCIAL INTELLIGENCE</p></section>
    <main className="auth-main"><div className="auth-form-wrap"><div className="mobile-auth-brand"><a href="/" className="brand-link"><img src="/logo.svg" alt="" />Indus</a><a href="/"><ArrowLeft />Home</a></div><p className="auth-eyebrow">{eyebrow}</p><h2>{heading}</h2><p className="auth-intro">{mode === 'signup' ? 'Create an account to save companies and generated research.' : mode === 'signin' ? 'Sign in to return to your watchlist, reports, and company analysis.' : 'Use the email associated with your Indus account.'}</p>
      <form onSubmit={submit} className="auth-form">
        {mode === 'signup' && <div className="name-grid"><label>First name<input value={firstName} onChange={e => setFirstName(e.target.value)} required autoComplete="given-name" /></label><label>Last name<input value={lastName} onChange={e => setLastName(e.target.value)} required autoComplete="family-name" /></label></div>}
        <label>Email<div className="input-wrap"><Mail/><input type="email" value={email} onChange={e => setEmail(e.target.value)} required autoComplete="email" placeholder="you@example.com" /></div></label>
        {(mode === 'signin' || mode === 'signup' || mode === 'reset') && <label>Password<div className="input-wrap"><Lock/><input type={showPassword ? 'text' : 'password'} value={password} onChange={e => setPassword(e.target.value)} required minLength={mode === 'signin' ? 1 : 14} autoComplete={mode === 'signin' ? 'current-password' : 'new-password'} placeholder="Password"/><button type="button" onClick={() => setShowPassword(value => !value)} aria-label={showPassword ? 'Hide password' : 'Show password'}>{showPassword ? <EyeOff/> : <Eye/>}</button></div>{mode !== 'signin' && <span className="auth-password-help">Use at least 14 characters with uppercase, lowercase, a number, and a symbol.</span>}</label>}
        {(mode === 'confirm' || mode === 'reset') && <label>Verification code<input className="plain-input" value={code} onChange={e => setCode(e.target.value)} required inputMode="numeric" autoComplete="one-time-code" placeholder="Verification code" /></label>}
        {error && <p role="alert" className="auth-error">{error}</p>}{message && <p role="status" className="auth-message">{message}</p>}
        <button className="auth-submit" disabled={busy}>{busy ? <Loader2 className="animate-spin"/> : <>{button}<ArrowRight/></>}</button>
      </form>
      <div className="auth-actions">{mode === 'signin' ? <><button onClick={() => setMode('forgot')}>Forgot password?</button><p>New to Indus? <button onClick={() => setMode('signup')}>Create an account</button></p></> : <button onClick={() => { setMode('signin'); setError(''); setMessage('') }}>Back to sign in</button>}</div>
    </div></main>
  </div>
}
