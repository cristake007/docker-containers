import { useMutation, useQuery } from '@apollo/client/react'
import { type FormEvent, useState } from 'react'
import { logout } from '../api/auth'
import {
  CREATE_TASK_MUTATION,
  DELETE_TASK_MUTATION,
  type Task,
  TASKS_QUERY,
  UPDATE_TASK_MUTATION,
} from '../graphql/tasks'

interface TaskAppProps {
  email: string
  onLoggedOut: () => void
}

export function TaskApp({ email, onLoggedOut }: TaskAppProps) {
  const { data, loading, error, refetch } = useQuery<{ tasks: Task[] }>(TASKS_QUERY)
  const [title, setTitle] = useState('')
  const [createTask, { loading: creating }] = useMutation(CREATE_TASK_MUTATION)
  const [updateTask] = useMutation(UPDATE_TASK_MUTATION)
  const [deleteTask] = useMutation(DELETE_TASK_MUTATION)

  async function handleCreate(event: FormEvent) {
    event.preventDefault()
    if (!title.trim()) return
    await createTask({ variables: { title: title.trim() } })
    setTitle('')
    await refetch()
  }

  async function handleToggle(task: Task) {
    await updateTask({ variables: { id: task.id, done: !task.done } })
    await refetch()
  }

  async function handleDelete(task: Task) {
    await deleteTask({ variables: { id: task.id } })
    await refetch()
  }

  async function handleLogout() {
    await logout()
    onLoggedOut()
  }

  return (
    <div className="task-app">
      <header>
        <span>{email}</span>
        <button type="button" className="link" onClick={handleLogout}>
          Log out
        </button>
      </header>

      <form onSubmit={handleCreate} className="new-task">
        <input
          type="text"
          placeholder="New task"
          value={title}
          onChange={(event) => setTitle(event.target.value)}
          maxLength={255}
        />
        <button type="submit" disabled={creating || !title.trim()}>
          Add
        </button>
      </form>

      {loading && <p>Loading…</p>}
      {error && <p className="error">Could not load tasks.</p>}

      <ul className="tasks">
        {data?.tasks.map((task) => (
          <li key={task.id} className={task.done ? 'done' : ''}>
            <label>
              <input type="checkbox" checked={task.done} onChange={() => handleToggle(task)} />
              {task.title}
            </label>
            <button type="button" className="link" onClick={() => handleDelete(task)}>
              Delete
            </button>
          </li>
        ))}
      </ul>
      {data?.tasks.length === 0 && <p>No tasks yet.</p>}
    </div>
  )
}
