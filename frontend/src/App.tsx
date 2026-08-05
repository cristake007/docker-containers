import { useEffect, useState } from 'react'
import './App.css'
import { me } from './api/auth'
import { AuthenticatedApp } from './components/AuthenticatedApp'
import { AuthView } from './components/AuthView'

function App() {
  const [email, setEmail] = useState<string | null>(null)
  const [checking, setChecking] = useState(true)

  useEffect(() => {
    me()
      .then((user) => setEmail(user?.email ?? null))
      .finally(() => setChecking(false))
  }, [])

  if (checking) {
    return null
  }

  return (
    <div className="app">
      {email ? (
        <AuthenticatedApp email={email} onLoggedOut={() => setEmail(null)} />
      ) : (
        <AuthView onAuthenticated={setEmail} />
      )}
    </div>
  )
}

export default App
