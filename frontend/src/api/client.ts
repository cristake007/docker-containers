import { ApolloClient, InMemoryCache, createHttpLink } from '@apollo/client'

const graphqlUri = import.meta.env.VITE_GRAPHQL_URL ?? '/api/graphql'

// `credentials: 'include'` is what makes the browser send the httpOnly
// BEARER cookie set by the backend on login. There is no token in this
// file, and there never should be: the JWT is never readable from JS.
const httpLink = createHttpLink({
  uri: graphqlUri,
  credentials: 'include',
})

export const apolloClient = new ApolloClient({
  link: httpLink,
  cache: new InMemoryCache(),
  defaultOptions: {
    watchQuery: { fetchPolicy: 'network-only' },
    query: { fetchPolicy: 'network-only' },
  },
})
