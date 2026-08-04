import { useEffect, useState } from 'react'
import './App.css'
import { me } from './api/auth'
import { AuthView } from './components/AuthView'
import { TaskApp } from './components/TaskApp'

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
    <main className="app">
      {email ? (
        <TaskApp email={email} onLoggedOut={() => setEmail(null)} />
      ) : (
        <AuthView onAuthenticated={setEmail} />
      )}
    </main>
  )
}

export default App
