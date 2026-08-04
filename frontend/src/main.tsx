import { ApolloProvider } from '@apollo/client/react'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { apolloClient } from './api/client'
import './index.css'
import App from './App.tsx'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ApolloProvider client={apolloClient}>
      <App />
    </ApolloProvider>
  </StrictMode>,
)
