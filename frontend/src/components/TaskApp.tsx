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
import { Button } from './ui/button'
import { Input } from './ui/input'

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
    <div className="min-h-dvh bg-white text-black">
      <div className="mx-auto flex min-h-dvh max-w-xl flex-col px-6 py-10 sm:px-8">
        <header className="flex items-center justify-between gap-4 border-b border-black/10 pb-6">
          <span className="text-lg font-extrabold tracking-tight text-brand-blue">Tasks</span>
          <div className="flex items-center gap-4">
            <span className="text-sm text-black/60">{email}</span>
            <Button
              type="button"
              variant="ghost"
              size="sm"
              className="text-black/60 hover:text-brand-blue"
              onClick={handleLogout}
            >
              Log out
            </Button>
          </div>
        </header>

        <form onSubmit={handleCreate} className="mt-6 flex gap-3">
          <Input
            type="text"
            placeholder="New task"
            value={title}
            onChange={(event) => setTitle(event.target.value)}
            maxLength={255}
            className="flex-1"
          />
          <Button type="submit" disabled={creating || !title.trim()}>
            Add
          </Button>
        </form>

        {loading && <p className="mt-8 text-sm text-black/60">Loading…</p>}

        {error && (
          <div
            role="alert"
            className="mt-8 rounded-lg border border-brand-red/30 bg-brand-red/5 px-4 py-3 text-sm font-medium text-brand-red"
          >
            Could not load tasks.
          </div>
        )}

        {data && data.tasks.length > 0 && (
          <ul className="mt-8 flex flex-col gap-2">
            {data.tasks.map((task) => (
              <li
                key={task.id}
                className="flex items-center justify-between gap-3 rounded-lg border border-black/10 px-4 py-3"
              >
                <label className="flex flex-1 items-center gap-3 text-sm">
                  <input
                    type="checkbox"
                    checked={task.done}
                    onChange={() => handleToggle(task)}
                    className="h-4 w-4 accent-brand-blue"
                  />
                  <span className={task.done ? 'text-black/40 line-through' : 'text-black'}>
                    {task.title}
                  </span>
                </label>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="text-black/40 hover:text-brand-red"
                  onClick={() => handleDelete(task)}
                >
                  Delete
                </Button>
              </li>
            ))}
          </ul>
        )}

        {data && data.tasks.length === 0 && (
          <div className="mt-8 flex flex-col items-center gap-3 rounded-xl border border-dashed border-black/15 px-6 py-14 text-center">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-brand-blue/10 text-brand-blue">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="22"
                height="22"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.75"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden="true"
              >
                <line x1="8" y1="6" x2="20" y2="6" />
                <line x1="8" y1="12" x2="20" y2="12" />
                <line x1="8" y1="18" x2="20" y2="18" />
                <circle cx="4" cy="6" r="1" />
                <circle cx="4" cy="12" r="1" />
                <circle cx="4" cy="18" r="1" />
              </svg>
            </div>
            <p className="text-base font-semibold text-black">No tasks yet</p>
            <p className="max-w-[26ch] text-sm text-black/60">
              Add your first task above to start tracking your work.
            </p>
          </div>
        )}
      </div>
    </div>
  )
}
