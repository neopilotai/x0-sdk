import { relatedProjects, type VercelRelatedProject } from '@vercel/related-projects'

const defaultCloneOrigin = 'http://localhost:3000'

export function getCloneOrigin() {
  if (!process.env.VERCEL) return defaultCloneOrigin

  const configuredOrigin = process.env.V0_CLONE_ORIGIN
  const relatedProject = getRelatedProject()
  const resolvedOrigin =
    process.env.VERCEL_ENV === 'preview'
      ? getPreviewUrl(relatedProject) || configuredOrigin
      : configuredOrigin || getProductionUrl(relatedProject)

  if (!resolvedOrigin) {
    throw new Error(
      process.env.VERCEL_ENV === 'preview'
        ? 'Link the web app as a Vercel Related Project or set V0_CLONE_ORIGIN.'
        : 'V0_CLONE_ORIGIN is required when the web app is not a Vercel Related Project.',
    )
  }

  const url = new URL(resolvedOrigin)

  if (
    (url.protocol !== 'http:' && url.protocol !== 'https:') ||
    url.username ||
    url.password ||
    url.pathname !== '/' ||
    url.search ||
    url.hash
  ) {
    throw new Error('V0_CLONE_ORIGIN must be an HTTP(S) origin without a path.')
  }

  if (url.protocol !== 'https:') {
    throw new Error('V0_CLONE_ORIGIN must use HTTPS on Vercel.')
  }

  return url.origin
}

function getRelatedProject() {
  const projects = relatedProjects({ noThrow: true })

  if (projects.length > 1) {
    throw new Error('The preview proxy must have only the web app configured as a Related Project.')
  }

  return projects[0]
}

function getPreviewUrl(project?: VercelRelatedProject) {
  const host = project?.preview.customEnvironment || project?.preview.branch
  return host ? `https://${host}` : undefined
}

function getProductionUrl(project?: VercelRelatedProject) {
  const host = project?.production.alias || project?.production.url
  return host ? `https://${host}` : undefined
}
