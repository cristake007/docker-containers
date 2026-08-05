import { type FormEvent, useState } from 'react'
import { AuthError, login, register } from '../api/auth'
import { Alert, AlertDescription } from './ui/alert'
import { Button } from './ui/button'
import { Input } from './ui/input'
import { Label } from './ui/label'

interface AuthViewProps {
  onAuthenticated: (email: string) => void
}

interface FieldErrors {
  email?: string
  password?: string
}

function validateEmail(value: string): string | undefined {
  if (!value.trim()) return 'Email is required.'
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) return 'Enter a valid email address.'
  return undefined
}

function validatePassword(value: string): string | undefined {
  if (!value) return 'Password is required.'
  if (value.length < 8) return 'Password must be at least 8 characters.'
  return undefined
}

export function AuthView({ onAuthenticated }: AuthViewProps) {
  const [mode, setMode] = useState<'login' | 'register'>('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({})
  const [formError, setFormError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  function switchMode() {
    setFormError(null)
    setFieldErrors({})
    setMode(mode === 'login' ? 'register' : 'login')
  }

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    setFormError(null)

    const nextFieldErrors: FieldErrors = {
      email: validateEmail(email),
      password: validatePassword(password),
    }
    if (nextFieldErrors.email || nextFieldErrors.password) {
      setFieldErrors(nextFieldErrors)
      return
    }
    setFieldErrors({})

    setSubmitting(true)
    try {
      if (mode === 'register') {
        await register(email, password)
      }
      await login(email, password)
      onAuthenticated(email)
    } catch (err) {
      if (err instanceof AuthError) {
        setFormError(err.message)
        setFieldErrors(err.fieldErrors)
      } else {
        setFormError('Something went wrong. Please try again.')
      }
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="grid min-h-dvh grid-cols-1 md:grid-cols-[1fr_3fr]">
      <div className="relative z-10 flex items-center justify-center px-6 py-10 sm:px-8 md:shadow-[8px_0_24px_-8px_rgb(0_0_0_/_0.25)] lg:px-10">
        <div className="w-full max-w-xs">
          <span className="mb-8 block text-xl font-extrabold tracking-tight text-primary md:hidden">
            Workspace
          </span>

          <h1 className="text-2xl font-bold">{mode === 'login' ? 'Sign in' : 'Create account'}</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            {mode === 'login'
              ? 'Welcome back. Enter your details to continue.'
              : 'Set up an account to enter your workspace.'}
          </p>

          {formError && (
            <Alert variant="destructive" className="mt-5">
              <AlertDescription>{formError}</AlertDescription>
            </Alert>
          )}

          <form onSubmit={handleSubmit} noValidate className="mt-6 flex flex-col gap-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(event) => {
                  setEmail(event.target.value)
                  if (fieldErrors.email) {
                    setFieldErrors((prev) => ({ ...prev, email: undefined }))
                  }
                }}
                autoComplete="email"
                aria-invalid={Boolean(fieldErrors.email)}
                aria-describedby={fieldErrors.email ? 'email-error' : undefined}
              />
              {fieldErrors.email && (
                <p id="email-error" className="text-sm text-destructive">
                  {fieldErrors.email}
                </p>
              )}
            </div>

            <div className="flex flex-col gap-2">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(event) => {
                  setPassword(event.target.value)
                  if (fieldErrors.password) {
                    setFieldErrors((prev) => ({ ...prev, password: undefined }))
                  }
                }}
                autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
                aria-invalid={Boolean(fieldErrors.password)}
                aria-describedby={fieldErrors.password ? 'password-error' : undefined}
              />
              {fieldErrors.password && (
                <p id="password-error" className="text-sm text-destructive">
                  {fieldErrors.password}
                </p>
              )}
            </div>

            <Button type="submit" disabled={submitting} className="mt-1 w-full">
              {mode === 'login' ? 'Log in' : 'Create account'}
            </Button>
          </form>

          <Button type="button" variant="link" size="sm" className="mt-6 px-0" onClick={switchMode}>
            {mode === 'login' ? 'Need an account? Register' : 'Already have an account? Log in'}
          </Button>
        </div>
      </div>

      <div className="relative hidden overflow-hidden bg-primary px-16 py-16 md:flex md:flex-col md:justify-between lg:px-20">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 opacity-[0.06] [background-image:radial-gradient(circle_at_1px_1px,white_1px,transparent_0)] [background-size:28px_28px]"
        />
        <span className="relative text-4xl font-extrabold tracking-tight text-primary-foreground lg:text-5xl">
          Workspace
        </span>
        <p className="relative max-w-[22ch] text-lg text-primary-foreground/80">
          Everything starts here.
        </p>
      </div>
    </div>
  )
}
