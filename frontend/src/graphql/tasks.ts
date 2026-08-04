import { gql } from '@apollo/client'

export interface Task {
  id: string
  title: string
  done: boolean
  createdAt: string
}

export const TASKS_QUERY = gql`
  query Tasks {
    tasks {
      id
      title
      done
      createdAt
    }
  }
`

export const CREATE_TASK_MUTATION = gql`
  mutation CreateTask($title: String!) {
    createTask(input: { title: $title, done: false }) {
      task {
        id
        title
        done
        createdAt
      }
    }
  }
`

export const UPDATE_TASK_MUTATION = gql`
  mutation UpdateTask($id: ID!, $done: Boolean!) {
    updateTask(input: { id: $id, done: $done }) {
      task {
        id
        title
        done
        createdAt
      }
    }
  }
`

export const DELETE_TASK_MUTATION = gql`
  mutation DeleteTask($id: ID!) {
    deleteTask(input: { id: $id }) {
      task {
        id
      }
    }
  }
`
